import {
  Address,
  L1ToL2MessageStatus,
  L1TransactionReceipt,
  L2TransactionReceipt,
  getL1Network,
  getL2Network,
} from "@arbitrum/sdk";
import { ArbSys__factory } from "@arbitrum/sdk/dist/lib/abi/factories/ArbSys__factory";
import { Inbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Inbox__factory";
import { ARB_SYS_ADDRESS } from "@arbitrum/sdk/dist/lib/dataEntities/constants";
import { JsonRpcProvider } from "@ethersproject/providers";
import { expect } from "chai";
import { BigNumber, Signer, constants } from "ethers";
import { defaultAbiCoder, id, keccak256, parseEther, randomBytes } from "ethers/lib/utils";
import { RoundTripProposalCreator } from "../src-ts/proposalCreator";
import { GPMEvent, GovernorProposalMonitor } from "../src-ts/proposalMonitor";
import { ProposalStageStatus } from "../src-ts/proposalStage";
import { StageFactory, TrackerEventName } from "../src-ts/proposalPipeline";
import {
  ArbitrumTimelock,
  L1ArbitrumTimelock,
  L1ArbitrumTimelock__factory,
  L2ArbitrumGovernor,
  L2ArbitrumGovernor__factory,
  NoteStore,
  NoteStore__factory,
  TestUpgrade__factory,
  UpgradeExecutor,
  UpgradeExecutor__factory,
} from "../typechain-types";

const wait = async (ms: number) => new Promise((res) => setTimeout(res, ms));

export const mineBlock = async (signer: Signer, tag: string) => {
  console.log(
    `Mining block for ${tag}:${await signer.getAddress()}:${
      (await signer.provider!.getNetwork()).chainId
    }`
  );
  await (await signer.sendTransaction({ to: await signer.getAddress(), value: 0 })).wait();
};

const mineUntilStop = async (miner: Signer, state: { mining: boolean }, tag: string) => {
  while (state.mining) {
    await mineBlock(miner, tag);
    await wait(15000);
  }
};

interface L2GovConfig {
  readonly constitutionalGovernorAddr: string;
  readonly provider: JsonRpcProvider;
}

interface L1GovConfig {
  readonly timelockAddr: string;
  readonly provider: JsonRpcProvider;
}

interface UpgradeConfig {
  readonly upgradeExecutorAddr: string;
  readonly provider: JsonRpcProvider;
  readonly chainId: number;
}

interface UpgradePathConfig {
  readonly arbOneGovernorConfig: L2GovConfig;
  readonly l1Config: L1GovConfig;
  readonly upgradeConfig: UpgradeConfig;
}

class Proposal {
  constructor(
    public readonly upgradeAddr: string,
    public readonly upgradeValue: BigNumber,
    public readonly upgradeData: string,
    public readonly proposalDescription: string,
    public readonly pathConfig: UpgradePathConfig
  ) {}

  public async formItUp() {
    // start from the upgrade executor
    // the upgrade should have the function `upgrade` on it that accepts a single
    // arg "bytes memory data"
    const descriptionHash = id(this.proposalDescription);

    // the upgrade contract itself
    const upgradeTo = this.upgradeAddr;
    const upgradeCallData = this.upgradeData;
    const upgradeValue = this.upgradeValue;

    // the upgrade executor
    const iUpgradeExecutor = UpgradeExecutor__factory.createInterface();
    const upgradeExecutorCallData = iUpgradeExecutor.encodeFunctionData("execute", [
      upgradeTo,
      upgradeCallData,
    ]);
    const upgradeExecutorTo = this.pathConfig.upgradeConfig.upgradeExecutorAddr;
    const upgradeExecutorValue = upgradeValue;

    // the l1 timelock
    const l1TimelockTo = this.pathConfig.l1Config.timelockAddr;
    const l1Timelock = L1ArbitrumTimelock__factory.connect(
      l1TimelockTo,
      this.pathConfig.l1Config.provider
    );
    const minDelay = await l1Timelock.getMinDelay();

    const inbox = await (async () => {
      try {
        const l2Network = await getL2Network(this.pathConfig.upgradeConfig.chainId);
        return l2Network.ethBridge.inbox;
      } catch (err) {
        // just check this is an expected l1 chain id and throw if not
        await getL1Network(this.pathConfig.upgradeConfig.chainId);
        return null;
      }
    })();

    let l1To: string, l1Data: string, l1Value: BigNumber;
    if (inbox) {
      l1To = await l1Timelock.RETRYABLE_TICKET_MAGIC();
      l1Data = defaultAbiCoder.encode(
        ["address", "address", "uint256", "uint256", "uint256", "bytes"],
        [inbox, upgradeExecutorTo, upgradeExecutorValue, 0, 0, upgradeExecutorCallData]
      );
      // this value gets ignored from xchain upgrades
      l1Value = BigNumber.from(0);
    } else {
      l1To = upgradeExecutorTo;
      l1Data = upgradeExecutorCallData;
      l1Value = upgradeExecutorValue;
    }

    const l1TImelockScheduleCallData = l1Timelock.interface.encodeFunctionData("schedule", [
      l1To,
      l1Value,
      l1Data,
      constants.HashZero,
      descriptionHash,
      minDelay,
    ]);
    const l1OpId = await l1Timelock.callStatic.hashOperation(
      l1To,
      l1Value,
      l1Data,
      constants.HashZero,
      descriptionHash
    );
    const l1TimelockExecuteCallData = l1Timelock.interface.encodeFunctionData("execute", [
      l1To,
      l1Value,
      l1Data,
      constants.HashZero,
      descriptionHash,
    ]);
    const l1TimelockValue = l1Value;

    const iArbSys = ArbSys__factory.createInterface();
    const proposalCallData = iArbSys.encodeFunctionData("sendTxToL1", [
      l1TimelockTo,
      l1TImelockScheduleCallData,
    ]);

    const arbGovInterface = L2ArbitrumGovernor__factory.createInterface();
    const proposeTo = this.pathConfig.arbOneGovernorConfig.constitutionalGovernorAddr;
    const proposeData = arbGovInterface.encodeFunctionData("propose", [
      [ARB_SYS_ADDRESS],
      [0],
      [proposalCallData],
      this.proposalDescription,
    ]);

    const l2OpId = await l1Timelock.callStatic.hashOperationBatch(
      [ARB_SYS_ADDRESS],
      [0],
      [proposalCallData],
      constants.HashZero,
      descriptionHash
    );

    const proposalId = keccak256(
      defaultAbiCoder.encode(
        ["address[]", "uint256[]", "bytes[]", "bytes32"],
        [[ARB_SYS_ADDRESS], [0], [proposalCallData], descriptionHash]
      )
    );

    const queueCallData = arbGovInterface.encodeFunctionData("queue", [
      [ARB_SYS_ADDRESS],
      [0],
      [proposalCallData],
      descriptionHash,
    ]);

    const l2ExecuteCallData = arbGovInterface.encodeFunctionData("execute", [
      [ARB_SYS_ADDRESS],
      [0],
      [proposalCallData],
      descriptionHash,
    ]);

    return {
      l2Gov: {
        proposalId: proposalId,
        operationId: l2OpId,
        propose: {
          to: proposeTo,
          data: proposeData,
        },
        queue: {
          to: proposeTo,
          data: queueCallData,
        },
        execute: {
          to: proposeTo,
          data: l2ExecuteCallData,
        },
      },
      l1Gov: {
        operationId: l1OpId,
        retryableDataLength: (upgradeExecutorCallData.length - 2) / 2,
        execute: {
          to: l1TimelockTo,
          data: l1TimelockExecuteCallData,
          value: l1TimelockValue,
        },
      },
    };
  }
}

// wait for the proposal to start, we need to increase the l2's view of the l1 block number by 1
const mineBlocksAndWaitForProposalState = async (
  l2GovernorContract: L2ArbitrumGovernor,
  proposalId: string,
  state: number,
  tag: string,
  localMiners?: {
    l1Signer: Signer;
    l2Signer: Signer;
  }
) => {
  while (true) {
    if (localMiners) {
      await mineBlock(localMiners.l1Signer, tag + "-l1signer");
      await mineBlock(localMiners.l2Signer, tag + "-l2signer");
    } else {
      await wait(1000);
    }
    const propState = await l2GovernorContract.state(proposalId);
    if (propState === state) break;
  }
};

const noteExists = (noteStore: NoteStore, noteId: string) =>
  new Promise<void>(async (resolve) => {
    while (true) {
      if (await noteStore.exists(noteId)) {
        resolve();
        break;
      }
      await wait(1000);
    }
  });

export const l2L1MonitoringValueTest = async (
  l1Signer: Signer,
  l2Signer: Signer,
  proposer: Signer,
  l1UpgradeExecutor: UpgradeExecutor,
  l1TimelockContract: L1ArbitrumTimelock,
  l2GovernorContract: L2ArbitrumGovernor,
  localMiners?: {
    l1Signer: Signer;
    l2Signer: Signer;
  }
) => {
  // give some tokens to the governor contract
  const noteStore = await new NoteStore__factory(l1Signer).deploy();
  const testUpgrade = await new TestUpgrade__factory(l1Signer).deploy();
  const note = "0x" + Buffer.from(randomBytes(32)).toString("hex");
  const upgradeValue = parseEther("0.000001");
  const noteId = await noteStore.noteId(
    l1UpgradeExecutor.address,
    l1TimelockContract.address,
    note,
    upgradeValue
  );
  const upgradeExecution = testUpgrade.interface.encodeFunctionData("upgradeWithValue", [
    noteStore.address,
    note,
  ]);

  const proposalString = "Prop2.2: Test transfer tokens and value on L1";
  const propCreator = new RoundTripProposalCreator(
    {
      provider: l1Signer.provider! as JsonRpcProvider,
      timelockAddr: l1TimelockContract.address,
    },
    [
      {
        provider: l1Signer.provider! as JsonRpcProvider,
        upgradeExecutorAddr: l1UpgradeExecutor.address,
      },
    ]
  );
  const proposal = await propCreator.create(
    [testUpgrade.address],
    [upgradeValue],
    [upgradeExecution],
    proposalString
  );

  const stageFactory = new StageFactory(l2Signer, l1Signer, l2Signer);
  const proposalMonitor = new GovernorProposalMonitor(
    l2GovernorContract.address,
    l2Signer.provider!,
    1000,
    5,
    await l2Signer.provider!.getBlockNumber(),
    stageFactory,
    true
  );

  proposalMonitor.on(TrackerEventName.TRACKER_STATUS, (e: GPMEvent) => {
    console.log(
      `Proposal status update:  Gov:${e.originAddress}, Prop:${e.identifier}  Stage:${
        e.stage
      } Status:${ProposalStageStatus[e.status]}`
    );
  });

  proposalMonitor.on(TrackerEventName.TRACKER_ERRORED, (e) => console.error(e));

  // send the proposal
  const receipt = await (
    await proposer.sendTransaction({
      to: l2GovernorContract.address,
      data: proposal.encode(),
    })
  ).wait();

  await proposalMonitor.monitorSingleProposal(receipt);

  // put the l2 value in the l1 timelock
  await (
    await l1Signer.sendTransaction({
      to: l1TimelockContract.address,
      value: upgradeValue,
    })
  ).wait();

  // wait a while then cast a vote
  await mineBlocksAndWaitForProposalState(l2GovernorContract, proposal.id(), 1, "waitforpropl2L1val", localMiners);
  await (await l2GovernorContract.connect(proposer).castVote(proposal.id(), 1)).wait();

  const noteBefore = await noteStore.exists(noteId);
  expect(noteBefore, "Note exists before").to.be.false;

  await mineBlocksUntilComplete(noteExists(noteStore, noteId), "waitfornotel2L1val", localMiners);

  const noteAfter = await noteStore.exists(noteId);
  expect(noteAfter, "Note exists after").to.be.true;
};

const mineBlocksUntilComplete = async (
  completion: Promise<void>,
  tag: string,
  localMiners?: {
    l1Signer: Signer;
    l2Signer: Signer;
  }
) => {
  return new Promise<void>(async (resolve, reject) => {
    let mining = true;
    completion
      .then(() => {
        mining = false;
        resolve();
      })
      .catch((a) => {
        mining = false;
        reject(a);
      });

    while (mining) {
      if (localMiners) {
        await mineBlock(localMiners.l1Signer, tag + "-l1signer");
        await mineBlock(localMiners.l2Signer, tag + "-l2signer");
      }
      await wait(500);
    }
  });
};

export const l2L1L2MonitoringValueTest = async (
  l1Signer: Signer,
  l2Signer: Signer,
  proposer: Signer,
  l2UpgradeExecutor: UpgradeExecutor,
  l1TimelockContract: L1ArbitrumTimelock,
  l2GovernorContract: L2ArbitrumGovernor,
  localMiners?: {
    l1Signer: Signer;
    l2Signer: Signer;
  }
) => {
  const noteStore = await new NoteStore__factory(l2Signer).deploy();
  const testUpgrade = await new TestUpgrade__factory(l2Signer).deploy();
  const note = "0x" + Buffer.from(randomBytes(32)).toString("hex");
  const upgradeValue = parseEther("0.0000011");
  const noteId = await noteStore.noteId(
    l2UpgradeExecutor.address,
    new Address(l1TimelockContract.address).applyAlias().value,
    note,
    upgradeValue
  );
  const transferExecution = testUpgrade.interface.encodeFunctionData("upgradeWithValue", [
    noteStore.address,
    note,
  ]);

  const proposalString = "Prop6: Test transfer tokens on round trip";
  const propCreator = new RoundTripProposalCreator(
    {
      provider: l1Signer.provider! as JsonRpcProvider,
      timelockAddr: l1TimelockContract.address,
    },
    [
      {
        provider: l2Signer.provider! as JsonRpcProvider,
        upgradeExecutorAddr: l2UpgradeExecutor.address,
      },
    ]
  );
  const proposal = await propCreator.create(
    [testUpgrade.address],
    [upgradeValue],
    [transferExecution],
    proposalString
  );
  const stageFactory = new StageFactory(l2Signer, l1Signer, l2Signer);
  const proposalMonitor = new GovernorProposalMonitor(
    l2GovernorContract.address,
    l2Signer.provider!,
    1000,
    5,
    await l2Signer.provider!.getBlockNumber(),
    stageFactory,
    true
  );

  proposalMonitor.on(TrackerEventName.TRACKER_STATUS, (e: GPMEvent) => {
    console.log(
      `Proposal status update:  Gov:${e.originAddress}, Prop:${e.identifier}  Stage:${
        e.stage
      } Status:${ProposalStageStatus[e.status]}`
    );
  });

  proposalMonitor.on(TrackerEventName.TRACKER_ERRORED, (e) => console.error(e));

  // send the proposal
  const receipt = await (
    await proposer.sendTransaction({
      to: l2GovernorContract.address,
      data: proposal.encode(),
    })
  ).wait();

  await proposalMonitor.monitorSingleProposal(receipt);

  // put the l2 value in the l1 timelock
  await (
    await l1Signer.sendTransaction({
      to: l1TimelockContract.address,
      value: upgradeValue,
    })
  ).wait();

  // wait a while then cast a vote
  await mineBlocksAndWaitForProposalState(l2GovernorContract, proposal.id(), 1, "waitforpropl2L1L2val", localMiners);
  await (await l2GovernorContract.connect(proposer).castVote(proposal.id(), 1)).wait();

  const noteBefore = await noteStore.exists(noteId);
  expect(noteBefore, "Note exists before").to.be.false;

  await mineBlocksUntilComplete(noteExists(noteStore, noteId), "waitfornotel2L1L2val", localMiners);

  const noteAfter = await noteStore.exists(noteId);
  expect(noteAfter, "Note exists after").to.be.true;
};

export const l2L1MonitoringTest = async (
  l1Signer: Signer,
  l2Signer: Signer,
  proposer: Signer,
  l1UpgradeExecutor: UpgradeExecutor,
  l1TimelockContract: L1ArbitrumTimelock,
  l2GovernorContract: L2ArbitrumGovernor,
  localMiners?: {
    l1Signer: Signer;
    l2Signer: Signer;
  }
) => {
  const noteStore = await new NoteStore__factory(l1Signer).deploy();
  const testUpgrade = await new TestUpgrade__factory(l1Signer).deploy();
  const note = "0x" + Buffer.from(randomBytes(32)).toString("hex");
  const upgradeValue = BigNumber.from(0);
  const noteId = await noteStore.noteId(
    l1UpgradeExecutor.address,
    l1TimelockContract.address,
    note,
    upgradeValue
  );
  const upgradeExecution = testUpgrade.interface.encodeFunctionData("upgrade", [
    noteStore.address,
    note,
  ]);

  const proposalString = "Prop2.1: Test transfer tokens on L1";
  const propCreator = new RoundTripProposalCreator(
    {
      provider: l1Signer.provider! as JsonRpcProvider,
      timelockAddr: l1TimelockContract.address,
    },
    [
      {
        provider: l1Signer.provider! as JsonRpcProvider,
        upgradeExecutorAddr: l1UpgradeExecutor.address,
      },
    ]
  );
  const proposal = await propCreator.create(
    [testUpgrade.address],
    [BigNumber.from(0)],
    [upgradeExecution],
    proposalString
  );

  const stageFactory = new StageFactory(l2Signer, l1Signer, l2Signer);
  const proposalMonitor = new GovernorProposalMonitor(
    l2GovernorContract.address,
    l2Signer.provider!,
    1000,
    5,
    await l2Signer.provider!.getBlockNumber(),
    stageFactory,
    true
  );

  proposalMonitor.on(TrackerEventName.TRACKER_STATUS, (e: GPMEvent) => {
    console.log(
      `Proposal status update:  Gov:${e.originAddress}, Prop:${e.identifier}  Stage:${
        e.stage
      } Status:${ProposalStageStatus[e.status]}`
    );
  });

  proposalMonitor.on(TrackerEventName.TRACKER_ERRORED, (e) => console.error(e));

  // send the proposal
  const receipt = await (
    await proposer.sendTransaction({
      to: l2GovernorContract.address,
      data: proposal.encode(),
    })
  ).wait();

  await proposalMonitor.monitorSingleProposal(receipt);

  // wait a while then cast a vote
  await mineBlocksAndWaitForProposalState(l2GovernorContract, proposal.id(), 1, "waitforpropl2L1", localMiners);
  await (await l2GovernorContract.connect(proposer).castVote(proposal.id(), 1)).wait();

  const noteBefore = await noteStore.exists(noteId);
  expect(noteBefore, "Note exists before").to.be.false;

  await mineBlocksUntilComplete(noteExists(noteStore, noteId), "waitfornotel2L1",localMiners);

  const noteAfter = await noteStore.exists(noteId);
  expect(noteAfter, "Note exists after").to.be.true;

  return true;
};

export const l2L1L2MonitoringTest = async (
  l1Signer: Signer,
  l2Signer: Signer,
  proposer: Signer,
  l2UpgradeExecutor: UpgradeExecutor,
  l1TimelockContract: L1ArbitrumTimelock,
  l2GovernorContract: L2ArbitrumGovernor,
  localMiners?: {
    l1Signer: Signer;
    l2Signer: Signer;
  }
) => {
  const noteStore = await new NoteStore__factory(l2Signer).deploy();
  const testUpgrade = await new TestUpgrade__factory(l2Signer).deploy();
  const note = "0x" + Buffer.from(randomBytes(32)).toString("hex");
  const upgradeValue = BigNumber.from(0);
  const noteId = await noteStore.noteId(
    l2UpgradeExecutor.address,
    new Address(l1TimelockContract.address).applyAlias().value,
    note,
    upgradeValue
  );
  const upgradeExecution = testUpgrade.interface.encodeFunctionData("upgrade", [
    noteStore.address,
    note,
  ]);

  const proposalString = "Prop6: Test transfer tokens on round trip";
  const propCreator = new RoundTripProposalCreator(
    {
      provider: l1Signer.provider! as JsonRpcProvider,
      timelockAddr: l1TimelockContract.address,
    },
    [
      {
        provider: l2Signer.provider! as JsonRpcProvider,
        upgradeExecutorAddr: l2UpgradeExecutor.address,
      },
    ]
  );
  const proposal = await propCreator.create(
    [testUpgrade.address],
    [BigNumber.from(0)],
    [upgradeExecution],
    proposalString
  );

  const stageFactory = new StageFactory(l2Signer, l1Signer, l2Signer);
  const proposalMonitor = new GovernorProposalMonitor(
    l2GovernorContract.address,
    l2Signer.provider!,
    1000,
    5,
    await l2Signer.provider!.getBlockNumber(),
    stageFactory,
    true
  );

  proposalMonitor.on(TrackerEventName.TRACKER_STATUS, (e: GPMEvent) => {
    console.log(
      `Proposal status update:  Gov:${e.originAddress}, Prop:${e.identifier}  Stage:${
        e.stage
      } Status:${ProposalStageStatus[e.status]}`
    );
  });

  proposalMonitor.on(TrackerEventName.TRACKER_ERRORED, (e) => console.error(e));

  // send the proposal
  const receipt = await (
    await proposer.sendTransaction({
      to: l2GovernorContract.address,
      data: proposal.encode(),
    })
  ).wait();

  await proposalMonitor.monitorSingleProposal(receipt);

  // wait a while then cast a vote
  await mineBlocksAndWaitForProposalState(l2GovernorContract, proposal.id(), 1, "waitforpropL2L1L2", localMiners);
  await (await l2GovernorContract.connect(proposer).castVote(proposal.id(), 1)).wait();

  const noteBefore = await noteStore.exists(noteId);
  expect(noteBefore, "Note exists before").to.be.false;

  await mineBlocksUntilComplete(noteExists(noteStore, noteId), "waitfornoteL2L1L2", localMiners);

  const noteAfter = await noteStore.exists(noteId);
  expect(noteAfter, "Note exists after").to.be.true;
};

const execL1Component = async (
  l1Deployer: Signer,
  l2Deployer: Signer,
  l1Signer: Signer,
  l2Signer: Signer,
  l1TimelockContract: L1ArbitrumTimelock,
  l2Tx: L2TransactionReceipt,
  proposalSuccess: () => Promise<boolean>,
  crossChain: boolean,
  propForm?: Awaited<ReturnType<Proposal["formItUp"]>>
) => {
  const propFormNonEmpty = propForm!;
  const l2ToL1Messages = await l2Tx.getL2ToL1Messages(l1Signer);
  const withdrawMessage = await l2ToL1Messages[0];

  const state = { mining: true };
  await Promise.race([
    mineUntilStop(l1Deployer, state, "withdrawl1dep"),
    mineUntilStop(l2Deployer, state, "withdrawl2dep"),
    withdrawMessage.waitUntilReadyToExecute(l2Signer.provider!),
  ]);
  state.mining = false;

  await (await withdrawMessage.execute(l2Deployer.provider!)).wait();

  await wait(5000);

  const opId = propFormNonEmpty.l1Gov.operationId;
  while (true) {
    await mineBlock(l1Signer, "l1opreadyl1signer");
    await mineBlock(l2Signer, "l1opreadyl2signer");
    if (await l1TimelockContract.isOperationReady(opId)) break;
    await wait(1000);
  }

  // execute the proposal
  let value = BigNumber.from(0);
  if (crossChain) {
    const l2Network = await getL2Network(l2Deployer);
    const inbox = Inbox__factory.connect(l2Network.ethBridge.inbox, l1Deployer.provider!);
    const submissionFee = await inbox.callStatic.calculateRetryableSubmissionFee(
      propFormNonEmpty.l1Gov.retryableDataLength,
      0
    );
    value = submissionFee.mul(2);
  }

  const tx = await l1Signer.sendTransaction({
    to: propFormNonEmpty.l1Gov.execute.to,
    data: propFormNonEmpty.l1Gov.execute.data,
    value: value,
  });

  const rec = await tx.wait();

  expect(await proposalSuccess(), "L1 proposal success").to.be.true;
  return rec;
};

const proposeAndExecuteL2 = async (
  l2TimelockContract: ArbitrumTimelock,
  l2GovernorContract: L2ArbitrumGovernor,
  l1Deployer: Signer,
  l2Deployer: Signer,
  l2Signer: Signer,
  proposalSuccess: () => Promise<Boolean>,
  propFormed?: Awaited<ReturnType<Proposal["formItUp"]>>
) => {
  const propFormedNonEmpty = propFormed!;
  await (
    await l2Signer.sendTransaction({
      to: propFormedNonEmpty.l2Gov.propose.to,
      data: propFormedNonEmpty.l2Gov.propose.data,
    })
  ).wait();

  const proposalId = propFormedNonEmpty.l2Gov.proposalId;
  const proposalVotes = await l2GovernorContract.proposalVotes(proposalId);
  expect(proposalVotes, "Proposal exists").to.not.be.undefined;

  await mineBlocksAndWaitForProposalState(l2GovernorContract, proposalId, 1, "l2propstate1", {
    l1Signer: l1Deployer,
    l2Signer: l2Deployer,
  });
  // vote on the proposal
  expect(
    await (await l2GovernorContract.proposalVotes(proposalId)).forVotes.toString(),
    "Votes before"
  ).to.eq("0");
  await (await l2GovernorContract.connect(l2Signer).castVote(proposalId, 1)).wait();
  expect(await (await l2GovernorContract.proposalVotes(proposalId)).forVotes.gt(0), "Votes after")
    .to.be.true;

  // wait for proposal to be in success state
  await mineBlocksAndWaitForProposalState(l2GovernorContract, proposalId, 4, "l2propstate4", {
    l1Signer: l1Deployer,
    l2Signer: l2Deployer,
  });

  // queue the proposal
  await (
    await l2Signer.sendTransaction({
      to: propFormedNonEmpty.l2Gov.queue.to,
      data: propFormedNonEmpty.l2Gov.queue.data,
    })
  ).wait();

  await mineBlocksAndWaitForProposalState(l2GovernorContract, proposalId, 5, "l2propstate5", {
    l1Signer: l1Deployer,
    l2Signer: l2Deployer,
  });

  const opIdBatch = propFormedNonEmpty.l2Gov.operationId;
  while (!(await l2TimelockContract.isOperationReady(opIdBatch))) {
    await mineBlock(l1Deployer, "l2opreadyl1dep");
    await mineBlock(l2Deployer, "l2opreadyl2dep");
    await wait(1000);
  }

  const executionTx = await (
    await l2Signer.sendTransaction({
      to: propFormedNonEmpty.l2Gov.execute.to,
      data: propFormedNonEmpty.l2Gov.execute.data,
    })
  ).wait();
  expect(await proposalSuccess(), "Proposal not executed successfully").to.be.true;
  return executionTx;
};

export const l2L1ProposalTest = async (
  l1Signer: Signer,
  l2Signer: Signer,
  l1Deployer: Signer,
  l2Deployer: Signer,
  l1UpgradeExecutor: UpgradeExecutor,
  l2GovernorContract: L2ArbitrumGovernor,
  l1TimelockContract: L1ArbitrumTimelock,
  l2TimelockContract: ArbitrumTimelock
) => {
  const noteStore = await new NoteStore__factory(l1Deployer).deploy();
  const testUpgrade = await new TestUpgrade__factory(l1Deployer).deploy();
  const note = "0x" + Buffer.from(randomBytes(32)).toString("hex");
  const upgradeValue = BigNumber.from(0);
  const noteId = await noteStore.noteId(
    l1UpgradeExecutor.address,
    l1TimelockContract.address,
    note,
    upgradeValue
  );
  const upgradeExecution = testUpgrade.interface.encodeFunctionData("upgrade", [
    noteStore.address,
    note,
  ]);

  const proposalString = "Prop2: Test transfer tokens on L1";
  const proposal = new Proposal(
    testUpgrade.address,
    BigNumber.from(0),
    upgradeExecution,
    proposalString,
    {
      arbOneGovernorConfig: {
        constitutionalGovernorAddr: l2GovernorContract.address,
        provider: l2Deployer.provider! as JsonRpcProvider,
      },
      l1Config: {
        provider: l1Deployer.provider! as JsonRpcProvider,
        timelockAddr: l1TimelockContract.address,
      },
      upgradeConfig: {
        chainId: await l1Signer.getChainId(),
        provider: l2Deployer.provider! as JsonRpcProvider,
        upgradeExecutorAddr: l1UpgradeExecutor.address,
      },
    }
  );
  const formData = await proposal.formItUp();

  const proposalSuccess = async () => {
    return true;
  };

  const executionTx = await proposeAndExecuteL2(
    l2TimelockContract,
    l2GovernorContract,
    l1Deployer,
    l2Deployer,
    l2Signer,
    proposalSuccess,
    formData
  );

  const l2Transaction = new L2TransactionReceipt(executionTx);

  const noteBefore = await noteStore.exists(noteId);
  expect(noteBefore, "Note exists before").to.be.false;

  // it should be non zero at the end
  const l1ProposalSuccess = async () => {
    const noteAfter = await noteStore.exists(noteId);
    expect(noteAfter, "Note exists after").to.be.true;

    return true;
  };

  await execL1Component(
    l1Deployer,
    l2Deployer,
    l1Signer,
    l2Signer,
    l1TimelockContract,
    l2Transaction,
    l1ProposalSuccess,
    false,
    formData
  );
};

export const l2l1l2Proposal = async (
  l1Signer: Signer,
  l2Signer: Signer,
  l1Deployer: Signer,
  l2Deployer: Signer,
  l2GovernorContract: L2ArbitrumGovernor,
  l1TimelockContract: L1ArbitrumTimelock,
  l2TimelockContract: ArbitrumTimelock,
  l2UpgradeExecutor: UpgradeExecutor
) => {
  const noteStore = await new NoteStore__factory(l2Deployer).deploy();
  const testUpgrade = await new TestUpgrade__factory(l2Deployer).deploy();
  const note = "0x" + Buffer.from(randomBytes(32)).toString("hex");
  const upgradeValue = BigNumber.from(0);
  const noteId = await noteStore.noteId(
    l2UpgradeExecutor.address,
    new Address(l1TimelockContract.address).applyAlias().value,
    note,
    upgradeValue
  );
  const upgradeExecution = testUpgrade.interface.encodeFunctionData("upgrade", [
    noteStore.address,
    note,
  ]);

  const proposalString = "Prop3: Test transfer tokens on round trip";
  const l2Network = await getL2Network(l2Deployer);
  const proposal = new Proposal(
    testUpgrade.address,
    BigNumber.from(0),
    upgradeExecution,
    proposalString,
    {
      arbOneGovernorConfig: {
        constitutionalGovernorAddr: l2GovernorContract.address,
        provider: l2Deployer.provider! as JsonRpcProvider,
      },
      l1Config: {
        provider: l1Deployer.provider! as JsonRpcProvider,
        timelockAddr: l1TimelockContract.address,
      },
      upgradeConfig: {
        chainId: l2Network.chainID,
        provider: l2Deployer.provider! as JsonRpcProvider,
        upgradeExecutorAddr: l2UpgradeExecutor.address,
      },
    }
  );
  const formData = await proposal.formItUp();

  const proposalSuccess = async () => {
    return true;
  };

  const executionTx = await proposeAndExecuteL2(
    l2TimelockContract,
    l2GovernorContract,
    l1Deployer,
    l2Deployer,
    l2Signer,
    proposalSuccess,
    formData
  );

  const l2Transaction = new L2TransactionReceipt(executionTx);

  // it should be non zero at the end
  const l1ProposalSuccess = async () => {
    return true;
  };

  const l1Rec = new L1TransactionReceipt(
    await execL1Component(
      l1Deployer,
      l2Deployer,
      l1Signer,
      l2Signer,
      l1TimelockContract,
      l2Transaction,
      l1ProposalSuccess,
      true,
      formData
    )
  );

  const noteBefore = await noteStore.exists(noteId);
  expect(noteBefore, "Note exists before").to.be.false;

  const messages = await l1Rec.getL1ToL2Messages(l2Signer);
  const status = await messages[0].waitForStatus();

  expect(status.status, "Funds deposited on L2").to.eq(L1ToL2MessageStatus.FUNDS_DEPOSITED_ON_L2);

  const manualRedeem = await messages[0].redeem();
  await manualRedeem.wait();
  const redeemStatus = await messages[0].waitForStatus();
  expect(redeemStatus.status, "Redeem").to.eq(L1ToL2MessageStatus.REDEEMED);

  const noteAfter = await noteStore.exists(noteId);
  expect(noteAfter, "Note exists after").to.be.true;
};
