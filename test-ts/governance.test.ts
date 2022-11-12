import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect, util } from "chai";
import {
  ArbitrumTimelock,
  ArbitrumTimelock__factory,
  L1ArbitrumTimelock,
  L1ArbitrumTimelock__factory,
  L1GovernanceFactory__factory,
  L2ArbitrumGovernor,
  L2ArbitrumGovernor__factory,
  L2ArbitrumToken__factory,
  L2GovernanceFactory__factory,
  ProxyAdmin__factory,
  TestUpgrade__factory,
  TransparentUpgradeableProxy__factory,
  UpgradeExecutor,
  UpgradeExecutor__factory,
} from "../typechain-types";
import { fundL1, fundL2, testSetup } from "./testSetup";
import { defaultAbiCoder, Interface } from "@ethersproject/abi";
import { BigNumber, BigNumberish, constants, Signer, Wallet } from "ethers";
import { id, keccak256, parseEther } from "ethers/lib/utils";
import {
  DeployedEvent as L1DeployedEvent,
  DeployedEventObject as L1DeployedEventObject,
} from "../typechain-types/src/L1GovernanceFactory";
import {
  DeployedEvent as L2DeployedEvent,
  DeployedEventObject as L2DeployedEventObject,
} from "../typechain-types/src/L2GovernanceFactory";
import {
  Address,
  getL2Network,
  InboxTools,
  L1ToL2MessageGasEstimator,
  L1ToL2MessageStatus,
  L1TransactionReceipt,
  L2TransactionReceipt,
} from "@arbitrum/sdk";
import {
  ARB_SYS_ADDRESS,
  NODE_INTERFACE_ADDRESS,
} from "@arbitrum/sdk/dist/lib/dataEntities/constants";
import { ArbitrumProvider } from "@arbitrum/sdk/dist/lib/utils/arbProvider";
import { ArbSys__factory } from "@arbitrum/sdk/dist/lib/abi/factories/ArbSys__factory";
import { Inbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Inbox__factory";
import { L1ToL2MessageCreator } from "@arbitrum/sdk/dist/lib/message/L1ToL2MessageCreator";
import { JsonRpcProvider } from "@ethersproject/providers";
// CHRIS: TODO: move typechain types to the right place?

// CHRIS: TODO: add tests for the token registration and bridging
// CHRIS: TODO: with the reverse and the normal gateways

const wait = async (ms: number) => new Promise((res) => setTimeout(res, ms));

describe("Governor", function () {
  // // We define a fixture to reuse the same setup in every test.
  // // We use loadFixture to run this setup once, snapshot that state,
  // // and reset Hardhat Network to that snapshot in every test.
  // async function deployOneYearLockFixture() {
  //   const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
  //   const ONE_GWEI = 1_000_000_000;

  //   const lockedAmount = ONE_GWEI;
  //   const unlockTime = (await time.latest()) + ONE_YEAR_IN_SECS;

  //   // Contracts are deployed using the first signer/account by default
  //   const [owner, otherAccount] = await ethers.getSigners();

  //   const Lock = await ethers.getContractFactory("Lock");
  //   const lock = await Lock.deploy(unlockTime, { value: lockedAmount });

  //   return { lock, unlockTime, lockedAmount, owner, otherAccount };
  // }

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

  class UpgradeProposalGenerator {
    private getProposalId(
      to: string[],
      value: BigNumberish[],
      data: string[],
      description: string
    ) {
      return keccak256(
        defaultAbiCoder.encode(
          ["address[]", "uint256[]", "bytes[]", "bytes32"],
          [to, value, data, description]
        )
      );
    }

    public async l1Upgrade(
      l1TimelockContract: L1ArbitrumTimelock,
      l1UpgradeExecutor: UpgradeExecutor,
      proposalDescription: string,
      upgradeAddr: string,
      upgradeValue: BigNumberish,
      upgradeData: string
    ) {
      const l1ProposalData = l1UpgradeExecutor.interface.encodeFunctionData(
        "execute",
        [upgradeAddr, upgradeData]
      );

      const scheduleData = l1TimelockContract.interface.encodeFunctionData(
        "schedule",
        [
          l1UpgradeExecutor.address,
          upgradeValue,
          l1ProposalData,
          constants.HashZero,
          id(proposalDescription),
          await l1TimelockContract.getMinDelay(),
        ]
      );

      // CHRIS: TODO: import the proper interface from the sdk?

      const arbSysInterface = new Interface([
        "function sendTxToL1(address destination, bytes calldata data) external payable returns (uint256)",
        "event L2ToL1Tx(address caller, address indexed destination, uint256 indexed hash, uint256 indexed position, uint256 arbBlockNum, uint256 ethBlockNum, uint256 timestamp, uint256 callvalue, bytes data)",
      ]);
      const l2Data = arbSysInterface.encodeFunctionData("sendTxToL1", [
        l1TimelockContract.address,
        scheduleData,
      ]);

      const l2Target = ARB_SYS_ADDRESS;
      const l2Value = upgradeValue;

      // CHRIS: TODO: move this to a function
      const l2ProposalId = this.getProposalId(
        [l2Target],
        [l2Value],
        [l2Data],
        id(proposalDescription)
      );

      const l1ProposalTo = l1UpgradeExecutor.address;
      const l1ProposalValue = upgradeValue;
      // incorrect
      const l1ProposalId = this.getProposalId(
        [l1ProposalTo],
        [l1ProposalValue],
        [l1ProposalData],
        id(proposalDescription)
      );

      return {
        l2Proposal: {
          target: l2Target,
          data: l2Data,
          value: l2Value,
          description: proposalDescription,
          id: l2ProposalId,
        },
        l1Schedule: {
          target: l1ProposalTo,
          data: l1ProposalData,
          value: l1ProposalValue,
          description: proposalDescription,
          operationId: l1ProposalId,
        },
      };
    }
    public l2Upgrade() {}
  }

  const deployGovernance = async (
    l1Deployer: Signer,
    l2Deployer: Signer,
    l2Signer: Signer
  ) => {
    const initialSupply = parseEther("1");
    // CHRIS: TODO: these are seconds! we should wait accordingly!
    const l1TimeLockDelay = 5;
    const l2TimeLockDelay = 7;
    const l2SignerAddr = await l2Signer.getAddress();
    // we use a non zero dummy address for the l1 token
    // it doesnt exist yet but we plan to upgrade the l2 token contract add this address
    const l1TokenAddress = "0x0000000000000000000000000000000000000001";

    // deploy L2
    const l2GovernanceFac = await new L2GovernanceFactory__factory(
      l2Deployer
    ).deploy();
    const l2GovDeployReceipt = await (
      await l2GovernanceFac.deploy(
        {
          _l2MinTimelockDelay: l2TimeLockDelay,
          _coreQuorumThreshold: 5,
          _l1Token: l1TokenAddress,
          _treasuryQuorumThreshold: 3,
          _l2TokenInitialSupply: initialSupply,
          _l2TokenOwner: l2SignerAddr,
          _l2UpgradeExecutors: [await l2Deployer.getAddress()],
          _proposalThreshold: 100,
          _votingDelay: 10,
          _votingPeriod: 10,
          _minPeriodAfterQuorum: 1
        },

        { gasLimit: 30000000 }
      )
    ).wait();

    const l2DeployResult = l2GovDeployReceipt.events?.filter(
      (e) => e.topics[0] === l2GovernanceFac.interface.getEventTopic("Deployed")
    )[0].args as unknown as L2DeployedEventObject;

    // deploy L1
    const l2Network = await getL2Network(l2Deployer);
    const l1GovernanceFac = await new L1GovernanceFactory__factory(
      l1Deployer
    ).deploy();
    const l1GovDeployReceipt = await (
      await l1GovernanceFac.deploy(
        l1TimeLockDelay,
        l2Network.ethBridge.inbox,
        l2DeployResult.coreTimelock
      )
    ).wait();
    const l1DeployResult = l1GovDeployReceipt.events?.filter(
      (e) => e.topics[0] === l1GovernanceFac.interface.getEventTopic("Deployed")
    )[0].args as unknown as L1DeployedEventObject;

    // after deploying transfer ownership of the upgrader to the l1 contract
    const l2UpgradeExecutor = UpgradeExecutor__factory.connect(
      l2DeployResult.executor,
      l2Deployer.provider!
    );
    const l1TimelockAddress = new Address(l1DeployResult.timelock);
    const ow = l1TimelockAddress.applyAlias().value;
    await (
      await l2UpgradeExecutor.connect(l2Deployer).grantRole(
        await l2UpgradeExecutor.EXECUTOR_ROLE(),
        ow
      )
    ).wait();
    await (
      await l2UpgradeExecutor.connect(l2Deployer).revokeRole(
        await l2UpgradeExecutor.EXECUTOR_ROLE(),
        await l2Deployer.getAddress()
      )
    ).wait();


    // return contract objects
    const l2TokenContract = L2ArbitrumToken__factory.connect(
      l2DeployResult.token,
      l2Deployer.provider!
    );

    const l2TimelockContract = ArbitrumTimelock__factory.connect(
      l2DeployResult.coreTimelock,
      l2Deployer.provider!
    );
    const l2GovernorContract = L2ArbitrumGovernor__factory.connect(
      l2DeployResult.coreGoverner,
      l2Deployer.provider!
    );
    const l2ProxyAdmin = ProxyAdmin__factory.connect(
      l2DeployResult.proxyAdmin,
      l2Deployer.provider!
    );

    const l1TimelockContract = L1ArbitrumTimelock__factory.connect(
      l1DeployResult.timelock,
      l1Deployer.provider!
    );
    const l1UpgradeExecutor = UpgradeExecutor__factory.connect(
      l1DeployResult.executor,
      l1Deployer.provider!
    );
    const l1ProxyAdmin = ProxyAdmin__factory.connect(
      l1DeployResult.proxyAdmin,
      l1Deployer.provider!
    );

    expect(
      await l2TokenContract.callStatic.delegates(l2SignerAddr),
      "L2 signer delegate before"
    ).to.eq(constants.AddressZero);
    await (
      await l2TokenContract.connect(l2Signer).delegate(l2SignerAddr)
    ).wait();
    expect(
      await l2TokenContract.callStatic.delegates(l2SignerAddr),
      "L2 signer delegate after"
    ).to.eq(l2SignerAddr);

    // mine some blocks to ensure that the votes are available for the previous block
    // make sure to mine at least 2 l1 block
    const arbSys = ArbSys__factory.connect(
      ARB_SYS_ADDRESS,
      l2Deployer.provider!
    );

    const arbProvider = new ArbitrumProvider(
      l2Deployer.provider! as JsonRpcProvider
    );
    const blockStart = await arbProvider.getBlock("latest");
    while (true) {
      const blockNext = await arbProvider.getBlock("latest");
      console.log("blocks", blockNext.l1BlockNumber, blockStart.l1BlockNumber);
      console.log(
        "votes available",
        (
          await l2GovernorContract.getVotes(
            await l2Signer.getAddress(),
            blockNext.l1BlockNumber - 1
          )
        ).toString()
      );
      await wait(1000);
      await mineBlock(l1Deployer);
      await mineBlock(l2Deployer);
      if (blockNext.l1BlockNumber - blockStart.l1BlockNumber > 5) break;
    }

    // await mineBlock(l2Signer);
    // await mineBlock(l2Signer);
    // await wait(1000);

    return {
      l2TokenContract,
      l2TimelockContract,
      l2GovernorContract,
      l2UpgradeExecutor,
      l2ProxyAdmin,
      l1TimelockContract,
      l1UpgradeExecutor,
      l1ProxyAdmin,
    };
  };

  const proposeAndExecuteL2 = async (
    l2TimelockContract: ArbitrumTimelock,
    l2GovernorContract: L2ArbitrumGovernor,
    l1Deployer: Signer,
    l2Deployer: Signer,
    l2Signer: Signer,
    proposalTo: string,
    proposalValue: BigNumber,
    proposalCalldata: string,
    proposalDescription: string,
    proposalSuccess: () => Promise<Boolean>
  ) => {
    console.log(
      "votes available",
      (
        await l2GovernorContract.getVotes(
          await l2Signer.getAddress(),
          (await l2GovernorContract.provider.getBlockNumber()) - 1
        )
      ).toString()
    );

    await (
      await l2GovernorContract
        .connect(l2Signer)
        .functions["propose(address[],uint256[],bytes[],string)"](
          [proposalTo],
          [proposalValue],
          [proposalCalldata],
          proposalDescription
        )
    ).wait();

    console.log("a");
    const proposalId = keccak256(
      defaultAbiCoder.encode(
        ["address[]", "uint256[]", "bytes[]", "bytes32"],
        [[proposalTo], [0], [proposalCalldata], id(proposalDescription)]
      )
    );
    console.log("statebefore", await l2GovernorContract.state(proposalId));
    const proposal = await l2GovernorContract.proposals(proposalId);
    expect(proposal, "Proposal exists").to.not.be.undefined;
    console.log("b");
    console.log(
      "proposal",
      await await l2GovernorContract.proposals(proposalId)
    );

    console.log("statebeforeb", await l2GovernorContract.state(proposalId));
    const l2VotingDelay = await l2GovernorContract.votingDelay();
    console.log("statebeforec", await l2GovernorContract.state(proposalId));
    console.log("l2VotingDelay", l2VotingDelay.toString());
    await mineBlocksAndWaitForProposalState(
      l1Deployer,
      l2Deployer,
      l2GovernorContract,
      proposalId,
      l2VotingDelay.toNumber(),
      1
    );
    console.log("c");
    // vote on the proposal
    expect(
      await (
        await l2GovernorContract.proposals(proposalId)
      ).forVotes.toString(),
      "Votes before"
    ).to.eq("0");
    await (
      await l2GovernorContract.connect(l2Signer).castVote(proposalId, 1)
    ).wait();
    expect(
      await (await l2GovernorContract.proposals(proposalId)).forVotes.gt(0),
      "Votes after"
    ).to.be.true;
    console.log("d");

    // wait for proposal to be in success state
    const l2VotingPeriod = (await l2GovernorContract.votingPeriod()).toNumber();
    console.log("voting period", l2VotingPeriod);
    await mineBlocksAndWaitForProposalState(
      l1Deployer,
      l2Deployer,
      l2GovernorContract,
      proposalId,
      l2VotingPeriod,
      4
    );
    console.log("e");

    // queue the proposal
    await (
      await l2GovernorContract.connect(l2Signer)["queue(uint256)"](proposalId)
    ).wait();
    console.log("f");

    const l2TimelockDelay = (await l2TimelockContract.getMinDelay()).toNumber();
    const start = Date.now();
    await mineBlocksAndWaitForProposalState(
      l1Deployer,
      l2Deployer,
      l2GovernorContract,
      proposalId,
      l2TimelockDelay,
      5
    );
    const end = Date.now();
    console.log("time", end - start);

    console.log("l2TimelockDelay", l2TimelockDelay);

    const opIdBatch = await l2TimelockContract.hashOperationBatch(
      [proposalTo],
      [proposalValue],
      [proposalCalldata],
      constants.HashZero,
      id(proposalDescription)
    );
    while (!(await l2TimelockContract.isOperationReady(opIdBatch))) {
      console.log(
        "isready",
        await l2TimelockContract.isOperationReady(opIdBatch)
      );

      console.log("exists", await l2TimelockContract.isOperation(opIdBatch));
      await mineBlock(l1Deployer);
      await mineBlock(l2Deployer);
      await wait(1000);
    }
    const executionTx = await (
      await l2GovernorContract.connect(l2Signer)["execute(uint256)"](proposalId)
    ).wait();
    expect(await proposalSuccess(), "Proposal not executed successfully").to.be
      .true;
    return executionTx;
  };

  it("L2 proposal", async () => {
    const { l1Signer, l2Signer, l1Deployer, l2Deployer } = await testSetup();
    // CHRIS: TODO: move these into test setup if we need them
    await fundL1(l1Signer, parseEther("1"));
    await fundL2(l2Signer, parseEther("1"));

    const {
      l2TokenContract,
      l2TimelockContract,
      l2GovernorContract,
      l2ProxyAdmin,
    } = await deployGovernance(l1Deployer, l2Deployer, l2Signer);

    // give some tokens to the timelock contract
    const l2UpgradeExecutor = 10;
    const testUpgraderBalanceEnd = 7;
    const randWalletEnd = l2UpgradeExecutor - testUpgraderBalanceEnd;
    const randWallet = Wallet.createRandom();

    // upgrade executor and upgrade
    const upExecutorLogic = await new UpgradeExecutor__factory(
      l2Deployer
    ).deploy();
    const testUpgradeExecutor = UpgradeExecutor__factory.connect(
      (
        await new TransparentUpgradeableProxy__factory(l2Deployer).deploy(
          upExecutorLogic.address,
          l2ProxyAdmin.address,
          "0x"
        )
      ).address,
      l2Deployer.provider!
    );

    await (
      await l2TokenContract
        .connect(l2Signer)
        .transfer(testUpgradeExecutor.address, l2UpgradeExecutor)
    ).wait();
    expect(
      (await l2TokenContract.balanceOf(testUpgradeExecutor.address)).toNumber(),
      "Upgrade executor balance start"
    ).to.eq(l2UpgradeExecutor);

    await (
      await testUpgradeExecutor
        .connect(l2Deployer)
        .initialize(testUpgradeExecutor.address, [l2TimelockContract.address])
    ).wait();
    const testUpgrade = await new TestUpgrade__factory(l2Deployer).deploy();

    // create a proposal for transfering tokens to rand wallet
    const proposalString = "Prop1: Test transfer tokens on L2";
    const transferProposal = testUpgrade.interface.encodeFunctionData(
      "upgrade",
      [l2TokenContract.address, randWallet.address, randWalletEnd]
    );

    const upgradeProposal = testUpgradeExecutor.interface.encodeFunctionData(
      "execute",
      [testUpgrade.address, transferProposal]
    );

    expect(
      (await l2TokenContract.balanceOf(randWallet.address)).toNumber(),
      "Wallet balance before"
    ).to.eq(0);

    const proposalSuccess = async () => {
      expect(
        (await l2TokenContract.balanceOf(randWallet.address)).toNumber(),
        "Wallet balance after"
      ).to.eq(randWalletEnd);
      expect(
        (
          await l2TokenContract.balanceOf(testUpgradeExecutor.address)
        ).toNumber(),
        "Test upgrader balance after"
      ).to.eq(testUpgraderBalanceEnd);

      return true;
    };

    await proposeAndExecuteL2(
      l2TimelockContract,
      l2GovernorContract,
      l1Deployer,
      l2Deployer,
      l2Signer,
      testUpgradeExecutor.address,
      BigNumber.from(0),
      upgradeProposal,
      proposalString,
      proposalSuccess
    );
  }).timeout(180000);

  it("L2-L1 proposal", async () => {
    const { l1Signer, l2Signer, l1Deployer, l2Deployer } = await testSetup();
    // CHRIS: TODO: move these into test setup if we need them
    await fundL1(l1Signer, parseEther("1"));
    await fundL2(l2Signer, parseEther("1"));

    const {
      l2TimelockContract,
      l1TimelockContract,
      l2GovernorContract,
      l1UpgradeExecutor,
    } = await deployGovernance(l1Deployer, l2Deployer, l2Signer);
    // give some tokens to the governor contract
    const l1UpgraderBalanceStart = 11;
    const l1TimelockBalanceEnd = 6;
    const randWalletEnd = l1UpgraderBalanceStart - l1TimelockBalanceEnd;
    const randWallet = Wallet.createRandom();

    // deploy a dummy token onto L1
    const erc20Impl = await (
      await new L2ArbitrumToken__factory(l1Deployer).deploy()
    ).deployed();
    const proxyAdmin = await (
      await new ProxyAdmin__factory(l1Deployer).deploy()
    ).deployed();
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
      await testErc20.initialize(
        addrOne,
        parseEther("2"),
        await l1Deployer.getAddress()
      )
    ).wait();

    // send some tokens to the l1 timelock
    await (
      await testErc20.transfer(
        l1UpgradeExecutor.address,
        l1UpgraderBalanceStart
      )
    ).wait();
    expect(
      (await testErc20.balanceOf(l1UpgradeExecutor.address)).toNumber(),
      "Upgrader balance start"
    ).to.eq(l1UpgraderBalanceStart);

    // CHRIS: TODO: packages have been published for token-bridge-contracts so we can remove that

    // proposal
    // send an l2 to l1 message to transfer tokens on the l1 timelock

    // create a proposal for transfering tokens to rand wallet
    const transferUpgrade = await new TestUpgrade__factory(l1Deployer).deploy();

    const proposalString = "Prop2: Test transfer tokens on L1";
    // 1. transfer tokens to rand from the l1 timelock
    const transferExecution = transferUpgrade.interface.encodeFunctionData(
      "upgrade",
      [testErc20.address, randWallet.address, randWalletEnd]
    );

    const upgradeProposal = l1UpgradeExecutor.interface.encodeFunctionData(
      "execute",
      [transferUpgrade.address, transferExecution]
    );

    // 2. schedule a transfer on l1
    const scheduleData = l1TimelockContract.interface.encodeFunctionData(
      "schedule",
      [
        l1UpgradeExecutor.address,
        0,
        upgradeProposal,
        constants.HashZero,
        id(proposalString),
        await l1TimelockContract.getMinDelay(),
      ]
    );

    // 3. send a message from l2 to l1 - by call the arbsys
    const arbSysInterface = new Interface([
      "function sendTxToL1(address destination, bytes calldata data) external payable returns (uint256)",
      "event L2ToL1Tx(address caller, address indexed destination, uint256 indexed hash, uint256 indexed position, uint256 arbBlockNum, uint256 ethBlockNum, uint256 timestamp, uint256 callvalue, bytes data)",
    ]);
    const proposalData = arbSysInterface.encodeFunctionData("sendTxToL1", [
      l1TimelockContract.address,
      scheduleData,
    ]);

    expect(
      (await testErc20.balanceOf(randWallet.address)).toNumber(),
      "Wallet balance before"
    ).to.eq(0);

    const proposalSuccess = async () => {
      return true;
    };

    const executionTx = await proposeAndExecuteL2(
      l2TimelockContract,
      l2GovernorContract,
      l1Deployer,
      l2Deployer,
      l2Signer,
      ARB_SYS_ADDRESS,
      BigNumber.from(0),
      proposalData,
      proposalString,
      proposalSuccess
    );

    const l2Transaction = new L2TransactionReceipt(executionTx);
    // check the balance is 0 to start
    const bal = (await testErc20.balanceOf(randWallet.address)).toNumber();
    expect(bal).to.eq(0);

    // it should be non zero at the end
    const l1ProposalSuccess = async () => {
      const balAfter = (
        await testErc20.balanceOf(randWallet.address)
      ).toNumber();
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
      l1UpgradeExecutor.address,
      BigNumber.from(0),
      upgradeProposal,
      proposalString,
      l1ProposalSuccess,
      false
    );
  }).timeout(360000);

  it.only("L2-L1-L2 proposal", async () => {
    const { l1Signer, l2Signer, l1Deployer, l2Deployer } = await testSetup();
    // CHRIS: TODO: move these into test setup if we need them
    await fundL1(l1Signer, parseEther("1"));
    await fundL2(l2Signer, parseEther("1"));

    const {
      l2TokenContract,
      l2TimelockContract,
      l1TimelockContract,
      l2GovernorContract,
      l2UpgradeExecutor,
    } = await deployGovernance(l1Deployer, l2Deployer, l2Signer);
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

    // CHRIS: TODO: packages have been published for token-bridge-contracts so we can remove that
    // pretty annoying that we have this problem - what about re-entrancy?
    // can we do this with just a gnosis safe?

    // proposal
    // send an l2 to l1 message to transfer tokens on the l1 timelock

    // receiver has to store replay protection otherwise we can execute the upgrade any time
    // normally this is done in the timelock? yeh it is, but what about execution
    // CHRIS: TODO: if we do an execute on the timelock directly what's the state of the proposal
    // CHRIS: TODO: in the governer? we hist schedule there, so presumably it moved?
    // CHRIS: TODO: yes it did. Could use another timelock contract since that does replay protection?
    // CHRIS: TODO: overkill

    // create a proposal for transfering tokens to rand wallet

    const proposalString = "Prop3: Test transfer tokens on round trip";
    // 1. transfer tokens to rand from the l1 timelock
    // we want to create a retryable ticket for this part

    const transferUpgrade = await new TestUpgrade__factory(l2Deployer).deploy();
    const transferExecution = transferUpgrade.interface.encodeFunctionData(
      "upgrade",
      [l2TokenContract.address, randWallet.address, randWalletEnd]
    );

    // 1. a
    const upgradeData = l2UpgradeExecutor.interface.encodeFunctionData(
      "execute",
      [
        transferUpgrade.address,
        transferExecution,
      ]
    );

    const l2Network = await getL2Network(l2Deployer);
    // 1. b. create a retryable ticket
    // const inboxTools =new L1ToL2MessageCreator.getTicketCreationRequest(
    //   {
    //     to: forwarder.address,
    //     data: forwardData,
    //     from: l1TimelockContract,
    //     l2CallValue: 0,
    //     callValueRefundAddress: await l2Signer.getAddress(),
    //     excessFeeRefundAddress: await l2Signer.getAddress(),
    //   }
    // )

    // target: proposalTo,
    // value: proposalValue,
    // predecessor: constants.HashZero,
    // salt: id(proposalString),
    // maxSubmissionCost: params.maxSubmissionCost,
    // excessFeeRefundAddress: l1SignerAddr,
    // callValueRefundAddress: l1SignerAddr,
    // gasLimit: params.gasLimit,
    // maxFeePerGas: params.maxFeePerGas,
    // payload: proposalCallData,
    // abi encode the upgrade data

    const executionData = defaultAbiCoder.encode(
      [
        "address",
        "address",
        "uint256",
        "uint256",
        "uint256",
        "bytes",
      ],
      [
        l2Network.ethBridge.inbox,
        l2UpgradeExecutor.address,
        0,
        0,
        0,
        upgradeData,
      ]
    );

    // l1TimelockContract.
    const magic = await l1TimelockContract.RETRYABLE_TICKET_MAGIC()

    // 2. schedule a transfer on l1
    const scheduleData = l1TimelockContract.interface.encodeFunctionData(
      "schedule",
      [
        magic,
        0,
        executionData,
        constants.HashZero,
        id(proposalString),
        await l1TimelockContract.getMinDelay(),
      ]
    );

    // 3. send a message from l2 to l1 - by call the arbsys
    const arbSysInterface = new Interface([
      "function sendTxToL1(address destination, bytes calldata data) external payable returns (uint256)",
      "event L2ToL1Tx(address caller, address indexed destination, uint256 indexed hash, uint256 indexed position, uint256 arbBlockNum, uint256 ethBlockNum, uint256 timestamp, uint256 callvalue, bytes data)",
    ]);
    const proposalData = arbSysInterface.encodeFunctionData("sendTxToL1", [
      l1TimelockContract.address,
      scheduleData,
    ]);

    // check the balance is 0 to start
    const bal = (
      await l2TokenContract.balanceOf(randWallet.address)
    ).toNumber();
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
      ARB_SYS_ADDRESS,
      BigNumber.from(0),
      proposalData,
      proposalString,
      proposalSuccess
    );

    const l2Transaction = new L2TransactionReceipt(executionTx);
    console.log("l2 executiong complete");

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
        l2Network.ethBridge.inbox,
        BigNumber.from(0),
        executionData,
        proposalString,
        l1ProposalSuccess,
        true
      )
    );

    const balanceBefore = await (
      await l2TokenContract.balanceOf(randWallet.address)
    ).toNumber();
    expect(balanceBefore, "rand balance before").to.eq(0);
    const messages = await l1Rec.getL1ToL2Messages(l2Signer);
    const status = await messages[0].waitForStatus();

    expect(status.status, "Funds deposited on L2").to.eq(
      L1ToL2MessageStatus.FUNDS_DEPOSITED_ON_L2
    );

    const manualRedeem = await messages[0].redeem();
    await manualRedeem.wait();
    const redeemStatus = await messages[0].waitForStatus();
    expect(redeemStatus.status, "Redeem").to.eq(L1ToL2MessageStatus.REDEEMED);

    const balanceAfter = await (
      await l2TokenContract.balanceOf(randWallet.address)
    ).toNumber();
    expect(balanceAfter, "balance after").to.eq(randWalletEnd);
  }).timeout(360000);

  const execL1Component = async (
    l1Deployer: Signer,
    l2Deployer: Signer,
    l1Signer: Signer,
    l2Signer: Signer,
    l1TimelockContract: L1ArbitrumTimelock,
    l2Tx: L2TransactionReceipt,
    proposalTo: string,
    proposalValue: BigNumber,
    proposalCallData: string,
    proposalString: string,
    proposalSuccess: () => Promise<boolean>,
    crossChain: boolean
  ) => {
    const l2ToL1Messages = await l2Tx.getL2ToL1Messages(l1Signer);
    const withdrawMessage = await l2ToL1Messages[0];

    console.log("waiting for outbox");
    const state = { mining: true };
    await Promise.race([
      mineUntilStop(l1Deployer, state),
      mineUntilStop(l2Deployer, state),
      withdrawMessage.waitUntilReadyToExecute(l2Signer.provider!),
    ]);
    state.mining = false;

    console.log("outbox waiting complete, now scheduling l1");

    await (await withdrawMessage.execute(l2Deployer.provider!)).wait();

    // CHRIS: TODO: replace this with what we should actually have here
    await wait(5000);
    console.log("executing l1");

    // execute the proposal
    let value = BigNumber.from( 0);
    if(crossChain) {
      const res = defaultAbiCoder.decode(
        ["address",
          "uint256" ,
          "address" ,
          "address" ,
          "uint256" ,
          "uint256" ,
          "bytes"], proposalCallData
      )
      const retryableCallData = res[6] as string;
      console.log(retryableCallData)
      const l2Network = await getL2Network(l2Deployer)
      const inbox = Inbox__factory.connect(l2Network.ethBridge.inbox, l1Deployer.provider!);
      const submissionFee = await inbox.callStatic.calculateRetryableSubmissionFee(
        (retryableCallData.length - 2) / 2, 0
      )
      value = submissionFee.mul(2);
    }

    const res = await l1TimelockContract
      .connect(l1Signer)
      .callStatic.execute(
        proposalTo,
        proposalValue,
        proposalCallData,
        constants.HashZero,
        id(proposalString), 
        {value: value}
      );
    const tx = await l1TimelockContract
      .connect(l1Signer)
      .execute(
        proposalTo,
        proposalValue,
        proposalCallData,
        constants.HashZero,
        id(proposalString),
        {value: value}
      );
    console.log("executing l1 wait");

    const rec = await tx.wait();
    console.log("executing l1 complete");

    expect(await proposalSuccess(), "L1 proposal success").to.be.true;

    return rec;
    // } else {
    //   const l1SignerAddr = await l1Signer.getAddress();
    //   const estimator = new L1ToL2MessageGasEstimator(l2Deployer.provider!);
    //   const funcParams = await estimator.populateFunctionParams((params) => {
    //     const data = l1TimelockContract.interface.encodeFunctionData(
    //       "executeCrossChain",
    //       [
    //         {
    //           target: proposalTo,
    //           value: proposalValue,
    //           predecessor: constants.HashZero,
    //           salt: id(proposalString),
    //           maxSubmissionCost: params.maxSubmissionCost,
    //           excessFeeRefundAddress: l1SignerAddr,
    //           callValueRefundAddress: l1SignerAddr,
    //           gasLimit: params.gasLimit,
    //           maxFeePerGas: params.maxFeePerGas,
    //           payload: proposalCallData,
    //         },
    //       ]
    //     );

    //     return {
    //       data,
    //       to: l1TimelockContract.address,
    //       from: l1SignerAddr,
    //       value: params.gasLimit
    //         .mul(params.maxFeePerGas)
    //         .add(params.maxSubmissionCost)
    //         .add(proposalValue),
    //     };
    //   }, l1Deployer.provider!);
    //   const tx = await l1Signer.sendTransaction({
    //     to: funcParams.to,
    //     data: funcParams.data,
    //     value: funcParams.value,
    //   });

    //   const rec = await tx.wait();
    //   expect(await proposalSuccess(), "L1 proposal success").to.be.true;
    //   return rec;
    // }
  };

  const mineUntilStop = async (miner: Signer, state: { mining: boolean }) => {
    while (state.mining) {
      console.log("mine block");
      await mineBlock(miner);
      await wait(15000);
    }
  };

  const mineBlock = async (signer: Signer) => {
    await (
      await signer.sendTransaction({ to: await signer.getAddress(), value: 0 })
    ).wait();
  };

  //   it("Should set the right owner", async function () {
  //     const { lock, owner } = await loadFixture(deployOneYearLockFixture);

  //     expect(await lock.owner()).to.equal(owner.address);
  //   });

  //   it("Should receive and store the funds to lock", async function () {
  //     const { lock, lockedAmount } = await loadFixture(
  //       deployOneYearLockFixture
  //     );

  //     expect(await ethers.provider.getBalance(lock.address)).to.equal(
  //       lockedAmount
  //     );
  //   });

  //   it("Should fail if the unlockTime is not in the future", async function () {
  //     // We don't use the fixture here because we want a different deployment
  //     const latestTime = await time.latest();
  //     const Lock = await ethers.getContractFactory("Lock");
  //     await expect(Lock.deploy(latestTime, { value: 1 })).to.be.revertedWith(
  //       "Unlock time should be in the future"
  //     );
  //   });
  // });

  // describe("Withdrawals", function () {
  //   describe("Validations", function () {
  //     it("Should revert with the right error if called too soon", async function () {
  //       const { lock } = await loadFixture(deployOneYearLockFixture);

  //       await expect(lock.withdraw()).to.be.revertedWith(
  //         "You can't withdraw yet"
  //       );
  //     });

  //     it("Should revert with the right error if called from another account", async function () {
  //       const { lock, unlockTime, otherAccount } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       // We can increase the time in Hardhat Network
  //       await time.increaseTo(unlockTime);

  //       // We use lock.connect() to send a transaction from another account
  //       await expect(lock.connect(otherAccount).withdraw()).to.be.revertedWith(
  //         "You aren't the owner"
  //       );
  //     });

  //     it("Shouldn't fail if the unlockTime has arrived and the owner calls it", async function () {
  //       const { lock, unlockTime } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       // Transactions are sent using the first signer by default
  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw()).not.to.be.reverted;
  //     });
  //   });

  //   describe("Events", function () {
  //     it("Should emit an event on withdrawals", async function () {
  //       const { lock, unlockTime, lockedAmount } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw())
  //         .to.emit(lock, "Withdrawal")
  //         .withArgs(lockedAmount, anyValue); // We accept any value as `when` arg
  //     });
  //   });

  //   describe("Transfers", function () {
  //     it("Should transfer the funds to the owner", async function () {
  //       const { lock, unlockTime, lockedAmount, owner } = await loadFixture(
  //         deployOneYearLockFixture
  //       );

  //       await time.increaseTo(unlockTime);

  //       await expect(lock.withdraw()).to.changeEtherBalances(
  //         [owner, lock],
  //         [lockedAmount, -lockedAmount]
  //       );
  //     });
  //   });
  // });
});
