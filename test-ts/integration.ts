import { expect } from "chai";
import { BigNumber, Signer, Wallet, constants } from "ethers";
import {
  ArbitrumTimelock,
  L1ArbitrumTimelock,
  L1ArbitrumTimelock__factory,
  L2ArbitrumGovernor,
  L2ArbitrumGovernor__factory,
  L2ArbitrumToken,
  L2ArbitrumToken__factory,
  ProxyAdmin__factory,
  TestUpgrade__factory,
  TransparentUpgradeableProxy__factory,
  UpgradeExecutor,
  UpgradeExecutor__factory,
} from "../typechain-types";
import { defaultAbiCoder, id, keccak256, parseEther } from "ethers/lib/utils";
import { RoundTripProposalCreator } from "../src-ts/proposalCreator";
import { JsonRpcProvider } from "@ethersproject/providers";
import { RoundTripProposalPipelineFactory } from "../src-ts/proposalStage";
import { GPMEventName, GovernorProposalMonitor } from "../src-ts/proposalMonitor";
import { L1ToL2MessageStatus, L1TransactionReceipt, L2TransactionReceipt, getL1Network, getL2Network } from "@arbitrum/sdk";
import { Inbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Inbox__factory";
import { ArbSys__factory } from "@arbitrum/sdk/dist/lib/abi/factories/ArbSys__factory";
import { ARB_SYS_ADDRESS } from "@arbitrum/sdk/dist/lib/dataEntities/constants";

const wait = async (ms: number) => new Promise((res) => setTimeout(res, ms));

const mineBlock = async (signer: Signer) => {
  await (await signer.sendTransaction({ to: await signer.getAddress(), value: 0 })).wait();
};

const mineUntilStop = async (miner: Signer, state: { mining: boolean }) => {
  while (state.mining) {
    await mineBlock(miner);
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
  l1Signer: Signer,
  l2Signer: Signer,
  l2GovernorContract: L2ArbitrumGovernor,
  proposalId: string,
  blockCount: number,
  state: number
) => {
  for (let index = 0; index < blockCount; index++) {
    await mineBlock(l1Signer);
    await mineBlock(l2Signer);
    if ((await l2GovernorContract.state(proposalId)) === state) break;
  }
};

export const l2L1MonitoringValueTest = async (
  l1Signer: Signer,
  l2Signer: Signer,
  l1Deployer: Signer,
  l2Deployer: Signer,
  l1UpgradeExecutor: UpgradeExecutor,
  l1TimelockContract: L1ArbitrumTimelock,
  l2GovernorContract: L2ArbitrumGovernor
) => {
  // give some tokens to the governor contract
  const l1UpgraderBalanceStart = 11;
  const l1TimelockBalanceEnd = 6;
  const randWalletEnd = l1UpgraderBalanceStart - l1TimelockBalanceEnd;
  const randWallet = Wallet.createRandom();

  // deploy a dummy token onto L1
  const erc20Impl = await (await new L2ArbitrumToken__factory(l1Deployer).deploy()).deployed();
  const proxyAdmin = await (await new ProxyAdmin__factory(l1Deployer).deploy()).deployed();
  const testErc20 = L2ArbitrumToken__factory.connect(
    (
      await (
        await new TransparentUpgradeableProxy__factory(l1Deployer).deploy(
          erc20Impl.address,
          proxyAdmin.address,
          "0x"
        )
      ).deployed()
    ).address,
    l1Deployer
  );
  const addrOne = "0x0000000000000000000000000000000000000001";
  await (
    await testErc20.initialize(addrOne, parseEther("2"), await l1Deployer.getAddress())
  ).wait();

  // send some tokens to the l1 timelock
  await (await testErc20.transfer(l1UpgradeExecutor.address, l1UpgraderBalanceStart)).wait();
  expect(
    (await testErc20.balanceOf(l1UpgradeExecutor.address)).toNumber(),
    "Upgrader balance start"
  ).to.eq(l1UpgraderBalanceStart);

  const transferUpgrade = await new TestUpgrade__factory(l1Deployer).deploy();
  const transferValue = parseEther("0.1");
  const transferExecution = transferUpgrade.interface.encodeFunctionData("upgradeWithValue", [
    testErc20.address,
    randWallet.address,
    randWalletEnd,
    randWallet.address,
    transferValue,
  ]);

  const proposalString = "Prop2.2: Test transfer tokens and value on L1";
  const propCreator = new RoundTripProposalCreator(
    {
      provider: l1Deployer.provider! as JsonRpcProvider,
      timelockAddr: l1TimelockContract.address,
    },
    {
      provider: l1Deployer.provider! as JsonRpcProvider,
      upgradeExecutorAddr: l1UpgradeExecutor.address,
    }
  );
  const proposal = await propCreator.create(
    transferUpgrade.address,
    transferValue,
    transferExecution,
    proposalString
  );

  const pipelineFactory = new RoundTripProposalPipelineFactory(l2Signer, l1Signer, l2Signer);

  const proposalMonitor = new GovernorProposalMonitor(
    l2GovernorContract.address,
    l2Signer.provider!,
    1000,
    5,
    await l2Signer.provider!.getBlockNumber(),
    pipelineFactory
  );
  proposalMonitor.start().catch((e) => console.error(e));
  proposalMonitor.on(GPMEventName.TRACKER_ERRORED, (e) => console.error(e));

  const trackerEnd = new Promise<void>((resolve) =>
    proposalMonitor.once(GPMEventName.TRACKER_ENDED, resolve)
  );

  // send the proposal
  await (
    await l2Signer.sendTransaction({
      to: l2GovernorContract.address,
      data: proposal.encode(),
    })
  ).wait();

  // put the l2 value in the l1 timelock
  await (
    await l1Signer.sendTransaction({
      to: l1TimelockContract.address,
      value: transferValue,
    })
  ).wait();

  // wait a while then cast a vote
  const l2VotingDelay = await l2GovernorContract.votingDelay();
  await mineBlocksAndWaitForProposalState(
    l1Deployer,
    l2Deployer,
    l2GovernorContract,
    proposal.id(),
    l2VotingDelay.toNumber(),
    1
  );
  await (await l2GovernorContract.connect(l2Signer).castVote(proposal.id(), 1)).wait();

  const mineBlocksUntilComplete = async (completion: Promise<void>) => {
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
        await mineBlock(l1Signer);
        await mineBlock(l2Signer);
        await wait(500);
      }
    });
  };

  const bal = (await testErc20.balanceOf(randWallet.address)).toNumber();
  expect(bal).to.eq(0);
  const ethBal = await randWallet.connect(l1Deployer.provider!).getBalance();
  expect(ethBal.toNumber(), "Eth bal before").to.eq(0);

  await mineBlocksUntilComplete(trackerEnd);

  const balAfter = (await testErc20.balanceOf(randWallet.address)).toNumber();
  expect(balAfter, "L1 balance after").to.eq(randWalletEnd);
  const ethBalAfter = await randWallet.connect(l1Deployer.provider!).getBalance();
  expect(ethBalAfter.toString(), "L1 Eth bal after").to.eq(transferValue.toString());
};

export const l2L1L2MonitoringValueTest = async (
  l1Signer: Signer,
  l2Signer: Signer,
  l1Deployer: Signer,
  l2Deployer: Signer,
  l2UpgradeExecutor: UpgradeExecutor,
  l2TokenContract: L2ArbitrumToken,
  l1TimelockContract: L1ArbitrumTimelock,
  l2GovernorContract: L2ArbitrumGovernor
) => {
  // give some tokens to the governor contract
  const l2UpgraderBalanceStart = 13;
  const l2UpgraderBalanceEnd = 3;
  const randWalletEnd = l2UpgraderBalanceStart - l2UpgraderBalanceEnd;
  const randWallet = Wallet.createRandom();

  // send some tokens to the forwarder
  await (
    await l2TokenContract
      .connect(l2Signer)
      .transfer(l2UpgradeExecutor.address, l2UpgraderBalanceStart)
  ).wait();
  expect(
    (await l2TokenContract.balanceOf(l2UpgradeExecutor.address)).toNumber(),
    "Upgrader balance start"
  ).to.eq(l2UpgraderBalanceStart);

  // create a proposal for transfering tokens to rand wallet
  const transferUpgrade = await new TestUpgrade__factory(l2Deployer).deploy();
  const transferValue = parseEther("0.11");
  const transferExecution = transferUpgrade.interface.encodeFunctionData("upgradeWithValue", [
    l2TokenContract.address,
    randWallet.address,
    randWalletEnd,
    randWallet.address,
    transferValue,
  ]);

  const proposalString = "Prop6: Test transfer tokens on round trip";
  const propCreator = new RoundTripProposalCreator(
    {
      provider: l1Deployer.provider! as JsonRpcProvider,
      timelockAddr: l1TimelockContract.address,
    },
    {
      provider: l2Deployer.provider! as JsonRpcProvider,
      upgradeExecutorAddr: l2UpgradeExecutor.address,
    }
  );
  const proposal = await propCreator.create(
    transferUpgrade.address,
    transferValue,
    transferExecution,
    proposalString
  );

  const pipelineFactory = new RoundTripProposalPipelineFactory(l2Signer, l1Signer, l2Signer);

  const proposalMonitor = new GovernorProposalMonitor(
    l2GovernorContract.address,
    l2Signer.provider!,
    1000,
    5,
    await l2Signer.provider!.getBlockNumber(),
    pipelineFactory
  );
  proposalMonitor.start().catch((e) => console.error(e));
  proposalMonitor.on(GPMEventName.TRACKER_ERRORED, (e) => console.error(e));

  const trackerEnd = new Promise<void>((resolve) =>
    proposalMonitor.once(GPMEventName.TRACKER_ENDED, resolve)
  );

  // send the proposal
  await (
    await l2Signer.sendTransaction({
      to: l2GovernorContract.address,
      data: proposal.encode(),
    })
  ).wait();

  // put the l2 value in the l1 timelock
  await (
    await l1Signer.sendTransaction({
      to: l1TimelockContract.address,
      value: transferValue,
    })
  ).wait();

  // wait a while then cast a vote
  const l2VotingDelay = await l2GovernorContract.votingDelay();
  await mineBlocksAndWaitForProposalState(
    l1Deployer,
    l2Deployer,
    l2GovernorContract,
    proposal.id(),
    l2VotingDelay.toNumber(),
    1
  );
  await (await l2GovernorContract.connect(l2Signer).castVote(proposal.id(), 1)).wait();

  // check the balance is 0 to start
  const bal = (await l2TokenContract.balanceOf(randWallet.address)).toNumber();
  expect(bal, "Wallet balance before").to.eq(0);

  const mineBlocksUntilComplete = async (completion: Promise<void>) => {
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
        await mineBlock(l1Signer);
        await mineBlock(l2Signer);
        await wait(500);
      }
    });
  };

  const balanceBefore = await (await l2TokenContract.balanceOf(randWallet.address)).toNumber();
  expect(balanceBefore, "rand balance before").to.eq(0);
  const ethBal = await randWallet.connect(l2Deployer.provider!).getBalance();
  expect(ethBal.toNumber(), "L2 Eth bal before").to.eq(0);

  await mineBlocksUntilComplete(trackerEnd);

  const balanceAfter = await (await l2TokenContract.balanceOf(randWallet.address)).toNumber();
  expect(balanceAfter, "balance after").to.eq(randWalletEnd);
  const ethBalAfter = await randWallet.connect(l2Deployer.provider!).getBalance();
  expect(ethBalAfter.toString(), "L2 Eth bal after").to.eq(transferValue.toString());
};

export const l2L1MonitoringTest = async (
  l1Signer: Signer,
  l2Signer: Signer,
  l1Deployer: Signer,
  l2Deployer: Signer,
  l1UpgradeExecutor: UpgradeExecutor,
  l1TimelockContract: L1ArbitrumTimelock,
  l2GovernorContract: L2ArbitrumGovernor
) => {
  // give some tokens to the governor contract
  const l1UpgraderBalanceStart = 11;
  const l1TimelockBalanceEnd = 6;
  const randWalletEnd = l1UpgraderBalanceStart - l1TimelockBalanceEnd;
  const randWallet = Wallet.createRandom();

  // deploy a dummy token onto L1
  const erc20Impl = await (await new L2ArbitrumToken__factory(l1Deployer).deploy()).deployed();
  const proxyAdmin = await (await new ProxyAdmin__factory(l1Deployer).deploy()).deployed();
  const testErc20 = L2ArbitrumToken__factory.connect(
    (
      await (
        await new TransparentUpgradeableProxy__factory(l1Deployer).deploy(
          erc20Impl.address,
          proxyAdmin.address,
          "0x"
        )
      ).deployed()
    ).address,
    l1Deployer
  );
  const addrOne = "0x0000000000000000000000000000000000000001";
  await (
    await testErc20.initialize(addrOne, parseEther("2"), await l1Deployer.getAddress())
  ).wait();

  // send some tokens to the l1 timelock
  await (await testErc20.transfer(l1UpgradeExecutor.address, l1UpgraderBalanceStart)).wait();
  expect(
    (await testErc20.balanceOf(l1UpgradeExecutor.address)).toNumber(),
    "Upgrader balance start"
  ).to.eq(l1UpgraderBalanceStart);

  const transferUpgrade = await new TestUpgrade__factory(l1Deployer).deploy();
  const transferExecution = transferUpgrade.interface.encodeFunctionData("upgrade", [
    testErc20.address,
    randWallet.address,
    randWalletEnd,
  ]);

  const proposalString = "Prop2.1: Test transfer tokens on L1";
  const propCreator = new RoundTripProposalCreator(
    {
      provider: l1Deployer.provider! as JsonRpcProvider,
      timelockAddr: l1TimelockContract.address,
    },
    {
      provider: l1Deployer.provider! as JsonRpcProvider,
      upgradeExecutorAddr: l1UpgradeExecutor.address,
    }
  );
  const proposal = await propCreator.create(
    transferUpgrade.address,
    BigNumber.from(0),
    transferExecution,
    proposalString
  );

  const pipelineFactory = new RoundTripProposalPipelineFactory(l2Signer, l1Signer, l2Signer);

  const proposalMonitor = new GovernorProposalMonitor(
    l2GovernorContract.address,
    l2Signer.provider!,
    1000,
    5,
    await l2Signer.provider!.getBlockNumber(),
    pipelineFactory
  );
  proposalMonitor.start().catch((e) => console.error(e));
  proposalMonitor.on(GPMEventName.TRACKER_ERRORED, (e) => console.error(e));

  const trackerEnd = new Promise<void>((resolve) =>
    proposalMonitor.once(GPMEventName.TRACKER_ENDED, resolve)
  );

  // send the proposal
  await (
    await l2Signer.sendTransaction({
      to: l2GovernorContract.address,
      data: proposal.encode(),
    })
  ).wait();

  // wait a while then cast a vote
  const l2VotingDelay = await l2GovernorContract.votingDelay();
  await mineBlocksAndWaitForProposalState(
    l1Deployer,
    l2Deployer,
    l2GovernorContract,
    proposal.id(),
    l2VotingDelay.toNumber(),
    1
  );
  await (await l2GovernorContract.connect(l2Signer).castVote(proposal.id(), 1)).wait();

  const mineBlocksUntilComplete = async (completion: Promise<void>) => {
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
        await mineBlock(l1Signer);
        await mineBlock(l2Signer);
        await wait(500);
      }
    });
  };

  const bal = (await testErc20.balanceOf(randWallet.address)).toNumber();
  expect(bal).to.eq(0);

  await mineBlocksUntilComplete(trackerEnd);

  const balAfter = (await testErc20.balanceOf(randWallet.address)).toNumber();
  expect(balAfter, "L1 balance after").to.eq(randWalletEnd);

  return true;
};

export const l2L1L2MonitoringTest = async (
  l1Signer: Signer,
  l2Signer: Signer,
  l1Deployer: Signer,
  l2Deployer: Signer,
  l2TokenContract: L2ArbitrumToken,
  l2UpgradeExecutor: UpgradeExecutor,
  l1TimelockContract: L1ArbitrumTimelock,
  l2GovernorContract: L2ArbitrumGovernor
) => {
  // give some tokens to the governor contract
  const l2UpgraderBalanceStart = 13;
  const l2UpgraderBalanceEnd = 3;
  const randWalletEnd = l2UpgraderBalanceStart - l2UpgraderBalanceEnd;
  const randWallet = Wallet.createRandom();

  // send some tokens to the forwarder
  await (
    await l2TokenContract
      .connect(l2Signer)
      .transfer(l2UpgradeExecutor.address, l2UpgraderBalanceStart)
  ).wait();
  expect(
    (await l2TokenContract.balanceOf(l2UpgradeExecutor.address)).toNumber(),
    "Upgrader balance start"
  ).to.eq(l2UpgraderBalanceStart);

  // create a proposal for transfering tokens to rand wallet
  const transferUpgrade = await new TestUpgrade__factory(l2Deployer).deploy();
  const transferExecution = transferUpgrade.interface.encodeFunctionData("upgrade", [
    l2TokenContract.address,
    randWallet.address,
    randWalletEnd,
  ]);

  const proposalString = "Prop6: Test transfer tokens on round trip";
  const propCreator = new RoundTripProposalCreator(
    {
      provider: l1Deployer.provider! as JsonRpcProvider,
      timelockAddr: l1TimelockContract.address,
    },
    {
      provider: l2Deployer.provider! as JsonRpcProvider,
      upgradeExecutorAddr: l2UpgradeExecutor.address,
    }
  );
  const proposal = await propCreator.create(
    transferUpgrade.address,
    BigNumber.from(0),
    transferExecution,
    proposalString
  );

  const pipelineFactory = new RoundTripProposalPipelineFactory(l2Signer, l1Signer, l2Signer);

  const proposalMonitor = new GovernorProposalMonitor(
    l2GovernorContract.address,
    l2Signer.provider!,
    1000,
    5,
    await l2Signer.provider!.getBlockNumber(),
    pipelineFactory
  );
  proposalMonitor.start().catch((e) => console.error(e));
  proposalMonitor.on(GPMEventName.TRACKER_ERRORED, (e) => console.error(e));

  const trackerEnd = new Promise<void>((resolve) =>
    proposalMonitor.once(GPMEventName.TRACKER_ENDED, resolve)
  );

  // send the proposal
  await (
    await l2Signer.sendTransaction({
      to: l2GovernorContract.address,
      data: proposal.encode(),
    })
  ).wait();

  // wait a while then cast a vote
  const l2VotingDelay = await l2GovernorContract.votingDelay();
  await mineBlocksAndWaitForProposalState(
    l1Deployer,
    l2Deployer,
    l2GovernorContract,
    proposal.id(),
    l2VotingDelay.toNumber(),
    1
  );
  await (await l2GovernorContract.connect(l2Signer).castVote(proposal.id(), 1)).wait();

  // check the balance is 0 to start
  const bal = (await l2TokenContract.balanceOf(randWallet.address)).toNumber();
  expect(bal, "Wallet balance before").to.eq(0);

  const mineBlocksUntilComplete = async (completion: Promise<void>) => {
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
        await mineBlock(l1Signer);
        await mineBlock(l2Signer);
        await wait(500);
      }
    });
  };

  const balanceBefore = await (await l2TokenContract.balanceOf(randWallet.address)).toNumber();
  expect(balanceBefore, "rand balance before").to.eq(0);

  await mineBlocksUntilComplete(trackerEnd);

  const balanceAfter = await (await l2TokenContract.balanceOf(randWallet.address)).toNumber();
  expect(balanceAfter, "balance after").to.eq(randWalletEnd);
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
    mineUntilStop(l1Deployer, state),
    mineUntilStop(l2Deployer, state),
    withdrawMessage.waitUntilReadyToExecute(l2Signer.provider!),
  ]);
  state.mining = false;

  await (await withdrawMessage.execute(l2Deployer.provider!)).wait();

  await wait(5000);

  const opId = propFormNonEmpty.l1Gov.operationId;
  while (true) {
    await mineBlock(l1Signer);
    await mineBlock(l2Signer);
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

  const l2VotingDelay = await l2GovernorContract.votingDelay();
  await mineBlocksAndWaitForProposalState(
    l1Deployer,
    l2Deployer,
    l2GovernorContract,
    proposalId,
    l2VotingDelay.toNumber(),
    1
  );
  // vote on the proposal
  expect(
    await (await l2GovernorContract.proposalVotes(proposalId)).forVotes.toString(),
    "Votes before"
  ).to.eq("0");
  await (await l2GovernorContract.connect(l2Signer).castVote(proposalId, 1)).wait();
  expect(await (await l2GovernorContract.proposalVotes(proposalId)).forVotes.gt(0), "Votes after")
    .to.be.true;

  // wait for proposal to be in success state
  const l2VotingPeriod = (await l2GovernorContract.votingPeriod()).toNumber();
  await mineBlocksAndWaitForProposalState(
    l1Deployer,
    l2Deployer,
    l2GovernorContract,
    proposalId,
    l2VotingPeriod,
    4
  );

  // queue the proposal
  await (
    await l2Signer.sendTransaction({
      to: propFormedNonEmpty.l2Gov.queue.to,
      data: propFormedNonEmpty.l2Gov.queue.data,
    })
  ).wait();

  const l2TimelockDelay = (await l2TimelockContract.getMinDelay()).toNumber();
  await mineBlocksAndWaitForProposalState(
    l1Deployer,
    l2Deployer,
    l2GovernorContract,
    proposalId,
    l2TimelockDelay,
    5
  );

  const opIdBatch = propFormedNonEmpty.l2Gov.operationId;
  while (!(await l2TimelockContract.isOperationReady(opIdBatch))) {
    await mineBlock(l1Deployer);
    await mineBlock(l2Deployer);
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
  const l1UpgraderBalanceStart = 11;
  const l1TimelockBalanceEnd = 6;
  const randWalletEnd = l1UpgraderBalanceStart - l1TimelockBalanceEnd;
  const randWallet = Wallet.createRandom();

  // deploy a dummy token onto L1
  const erc20Impl = await (await new L2ArbitrumToken__factory(l1Deployer).deploy()).deployed();
  const proxyAdmin = await (await new ProxyAdmin__factory(l1Deployer).deploy()).deployed();
  const testErc20 = L2ArbitrumToken__factory.connect(
    (
      await (
        await new TransparentUpgradeableProxy__factory(l1Deployer).deploy(
          erc20Impl.address,
          proxyAdmin.address,
          "0x"
        )
      ).deployed()
    ).address,
    l1Deployer
  );
  const addrOne = "0x0000000000000000000000000000000000000001";
  await (
    await testErc20.initialize(addrOne, parseEther("2"), await l1Deployer.getAddress())
  ).wait();

  // send some tokens to the l1 timelock
  await (await testErc20.transfer(l1UpgradeExecutor.address, l1UpgraderBalanceStart)).wait();
  expect(
    (await testErc20.balanceOf(l1UpgradeExecutor.address)).toNumber(),
    "Upgrader balance start"
  ).to.eq(l1UpgraderBalanceStart);

  // create a proposal for transfering tokens to rand wallet
  const transferUpgrade = await new TestUpgrade__factory(l1Deployer).deploy();
  const transferExecution = transferUpgrade.interface.encodeFunctionData("upgrade", [
    testErc20.address,
    randWallet.address,
    randWalletEnd,
  ]);
  const proposalString = "Prop2: Test transfer tokens on L1";
  const proposal = new Proposal(
    transferUpgrade.address,
    BigNumber.from(0),
    transferExecution,
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

  expect((await testErc20.balanceOf(randWallet.address)).toNumber(), "Wallet balance before").to.eq(
    0
  );

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
  // check the balance is 0 to start
  const bal = (await testErc20.balanceOf(randWallet.address)).toNumber();
  expect(bal).to.eq(0);

  // it should be non zero at the end
  const l1ProposalSuccess = async () => {
    const balAfter = (await testErc20.balanceOf(randWallet.address)).toNumber();
    expect(balAfter, "L1 balance after").to.eq(randWalletEnd);

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
  l2TokenContract: L2ArbitrumToken,
  l2UpgradeExecutor: UpgradeExecutor
) => {
  // give some tokens to the governor contract
  const l2UpgraderBalanceStart = 13;
  const l2UpgraderBalanceEnd = 3;
  const randWalletEnd = l2UpgraderBalanceStart - l2UpgraderBalanceEnd;
  const randWallet = Wallet.createRandom();

  // send some tokens to the forwarder
  await (
    await l2TokenContract
      .connect(l2Signer)
      .transfer(l2UpgradeExecutor.address, l2UpgraderBalanceStart)
  ).wait();
  expect(
    (await l2TokenContract.balanceOf(l2UpgradeExecutor.address)).toNumber(),
    "Upgrader balance start"
  ).to.eq(l2UpgraderBalanceStart);

  // create a proposal for transfering tokens to rand wallet

  const transferUpgrade = await new TestUpgrade__factory(l2Deployer).deploy();
  const transferExecution = transferUpgrade.interface.encodeFunctionData("upgrade", [
    l2TokenContract.address,
    randWallet.address,
    randWalletEnd,
  ]);
  const proposalString = "Prop3: Test transfer tokens on round trip";
  const l2Network = await getL2Network(l2Deployer);
  const proposal = new Proposal(
    transferUpgrade.address,
    BigNumber.from(0),
    transferExecution,
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

  // check the balance is 0 to start
  const bal = (await l2TokenContract.balanceOf(randWallet.address)).toNumber();
  expect(bal, "Wallet balance before").to.eq(0);
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

  const balanceBefore = await (await l2TokenContract.balanceOf(randWallet.address)).toNumber();
  expect(balanceBefore, "rand balance before").to.eq(0);
  const messages = await l1Rec.getL1ToL2Messages(l2Signer);
  const status = await messages[0].waitForStatus();

  expect(status.status, "Funds deposited on L2").to.eq(L1ToL2MessageStatus.FUNDS_DEPOSITED_ON_L2);

  const manualRedeem = await messages[0].redeem();
  await manualRedeem.wait();
  const redeemStatus = await messages[0].waitForStatus();
  expect(redeemStatus.status, "Redeem").to.eq(L1ToL2MessageStatus.REDEEMED);

  const balanceAfter = await (await l2TokenContract.balanceOf(randWallet.address)).toNumber();
  expect(balanceAfter, "balance after").to.eq(randWalletEnd);
};
