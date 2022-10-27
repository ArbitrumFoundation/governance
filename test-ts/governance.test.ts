import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect, util } from "chai";
import { ethers } from "hardhat";
import {
  ArbitrumTimelock,
  ArbitrumTimelock__factory,
  ERC20PermitUpgradeable__factory,
  Forwarder__factory,
  L1ArbitrumTimelock,
  L1ArbitrumTimelock__factory,
  L1GovernanceFactory__factory,
  L2ArbitrumGovernor,
  L2ArbitrumGovernor__factory,
  L2ArbitrumToken,
  L2ArbitrumToken__factory,
  L2GovernanceFactory__factory,
  ProxyAdmin__factory,
  TransparentUpgradeableProxy__factory,
} from "../typechain-types";
import { fundL1, fundL2, testSetup } from "./testSetup";
import { JsonRpcProvider, TransactionReceipt } from "@ethersproject/providers";
import { defaultAbiCoder, Interface } from "@ethersproject/abi";
import { BigNumber, constants, Signer, Wallet } from "ethers";
import {
  arrayify,
  id,
  keccak256,
  parseEther,
  toUtf8Bytes,
} from "ethers/lib/utils";
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
import { ARB_SYS_ADDRESS } from "@arbitrum/sdk/dist/lib/dataEntities/constants";
import { L1ToL2MessageCreator } from "@arbitrum/sdk/dist/lib/message/L1ToL2MessageCreator";
// CHRIS: TODO: move typechain types to the right place?

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
    }
    while (true) {
      await wait(100);
      if ((await l2GovernorContract.state(proposalId)) === state) break;
    }
  };

  const deployGovernance = async (
    l1Deployer: Signer,
    l2Deployer: Signer,
    l2Signer: Signer
  ) => {
    const initialSupply = parseEther("1");
    const l1TimeLockDelay = 5;
    const l2TimeLockDelay = 7;
    const l2SignerAddr = await l2Signer.getAddress();
    // we use a non zero dummy address for the l1 token
    // it doesnt exist yet but we plan to upgrade the l2 token contract add this address
    const l1TokenAddress = "0x0000000000000000000000000000000000000001";

    // deploy L2
    const l2TokenLogic = await new L2ArbitrumToken__factory(
      l2Deployer
    ).deploy();
    const l2TimelockLogic = await new ArbitrumTimelock__factory(
      l2Deployer
    ).deploy();
    const l2GovernanceLogic = await new L2ArbitrumGovernor__factory(
      l2Deployer
    ).deploy();
    const l2GovernanceFac = await new L2GovernanceFactory__factory(
      l2Deployer
    ).deploy();
    const l2GovDeployReceipt = await (
      await l2GovernanceFac.deploy(
        l2TimeLockDelay,
        l1TokenAddress,
        l2TokenLogic.address,
        initialSupply,
        l2SignerAddr,
        l2TimelockLogic.address,
        l2GovernanceLogic.address,
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
        l2DeployResult.timelock
      )
    ).wait();
    const l1DeployResult = l1GovDeployReceipt.events?.filter(
      (e) => e.topics[0] === l1GovernanceFac.interface.getEventTopic("Deployed")
    )[0].args as unknown as L1DeployedEventObject;

    // return contract objects
    const l2TokenContract = L2ArbitrumToken__factory.connect(
      l2DeployResult.token,
      l2Deployer.provider!
    );
    const l2TimelockContract = ArbitrumTimelock__factory.connect(
      l2DeployResult.timelock,
      l2Deployer.provider!
    );
    const l2GovernorContract = L2ArbitrumGovernor__factory.connect(
      l2DeployResult.governor,
      l2Deployer.provider!
    );
    const l1TimelockContract = L1ArbitrumTimelock__factory.connect(
      l1DeployResult.timelock,
      l1Deployer.provider!
    );

    expect(
      await l2TokenContract.callStatic.delegates(l2SignerAddr),
      "L2 signer delegate before"
    ).to.eq(constants.AddressZero);
    await l2TokenContract.connect(l2Signer).delegate(l2SignerAddr);
    expect(
      await l2TokenContract.callStatic.delegates(l2SignerAddr),
      "L2 signer delegate after"
    ).to.eq(l2SignerAddr);

    return {
      l2TokenContract,
      l2TimelockContract,
      l2GovernorContract,
      l1TimelockContract,
    };
  };

  const proposeAndExecuteL2 = async (
    l2TokenContract: L2ArbitrumToken,
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

    const proposalId = keccak256(
      defaultAbiCoder.encode(
        ["address[]", "uint256[]", "bytes[]", "bytes32"],
        [[proposalTo], [0], [proposalCalldata], id(proposalDescription)]
      )
    );
    const proposal = await l2GovernorContract.proposals(proposalId);
    expect(proposal, "Proposal exists").to.not.be.undefined;

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
      await l2GovernorContract.connect(l2Signer)["queue(uint256)"](proposalId)
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

    const executionTx = await (
      await l2GovernorContract.connect(l2Signer)["execute(uint256)"](proposalId)
    ).wait();
    expect(await proposalSuccess(), "Proposal not executed successfully").to.be
      .true;
    return executionTx;
  };

  it.skip("L2 proposal", async function () {
    const { l1Signer, l2Signer, l1Deployer, l2Deployer } = await testSetup();
    // CHRIS: TODO: move these into test setup if we need them
    await fundL1(l1Signer, parseEther("1"));
    await fundL2(l2Signer, parseEther("1"));

    const { l2TokenContract, l2TimelockContract, l2GovernorContract } =
      await deployGovernance(l1Deployer, l2Deployer, l2Signer);
    // give some tokens to the timelock contract
    const l2TimelockBalanceStart = 10;
    const l2TimelockBalanceEnd = 7;
    const randWalletEnd = l2TimelockBalanceStart - l2TimelockBalanceEnd;
    const randWallet = Wallet.createRandom();

    await (
      await l2TokenContract
        .connect(l2Signer)
        .transfer(l2TimelockContract.address, l2TimelockBalanceStart)
    ).wait();
    expect(
      (await l2TokenContract.balanceOf(l2TimelockContract.address)).toNumber(),
      "Timelock balance start"
    ).to.eq(l2TimelockBalanceStart);

    // create a proposal for transfering tokens to rand wallet
    const transferProposal = l2TokenContract.interface.encodeFunctionData(
      "transfer",
      [randWallet.address, randWalletEnd]
    );
    const proposalString = "Prop1: Test transfer tokens on L2";

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
          await l2TokenContract.balanceOf(l2TimelockContract.address)
        ).toNumber(),
        "Timelock balance after"
      ).to.eq(l2TimelockBalanceEnd);

      return true;
    };

    await proposeAndExecuteL2(
      l2TokenContract,
      l2TimelockContract,
      l2GovernorContract,
      l1Deployer,
      l2Deployer,
      l2Signer,
      l2TokenContract.address,
      BigNumber.from(0),
      transferProposal,
      proposalString,
      proposalSuccess
    );

    // the timelocks are the owners - instead of overriding the timelock obj
    // we should create a new one. Overriding would be
    // a) make sure we're called from the gateway, then continue?

    // const l2GovernanceFac = await new L2GovernanceFactory__factory(
    //   l2Signer
    // ).deploy();

    // const l1Governance = await l1GovernanceFac.deploy();
    // const deployReceipt = await (
    //   await l1Governance.deploy(l1TimeLockDelay)
    // ).wait();

    // console.log(deployReceipt)
  }).timeout(120000);

  it("L2-L1 proposal", async function () {
    const { l1Signer, l2Signer, l1Deployer, l2Deployer } = await testSetup();
    // CHRIS: TODO: move these into test setup if we need them
    await fundL1(l1Signer, parseEther("1"));
    await fundL2(l2Signer, parseEther("1"));

    const {
      l2TokenContract,
      l2TimelockContract,
      l1TimelockContract,
      l2GovernorContract,
    } = await deployGovernance(l1Deployer, l2Deployer, l2Signer);
    // give some tokens to the governor contract
    const l1TimelockBalanceStart = 11;
    const l1TimelockBalanceEnd = 6;
    const randWalletEnd = l1TimelockBalanceStart - l1TimelockBalanceEnd;
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
        l1TimelockContract.address,
        l1TimelockBalanceStart
      )
    ).wait();
    expect(
      (await testErc20.balanceOf(l1TimelockContract.address)).toNumber(),
      "Timelock balance start"
    ).to.eq(l1TimelockBalanceStart);

    // CHRIS: TODO: packages have been published for token-bridge-contracts so we can remove that

    // proposal
    // send an l2 to l1 message to transfer tokens on the l1 timelock

    // create a proposal for transfering tokens to rand wallet

    const proposalString = "Prop2: Test transfer tokens on L1";
    // 1. transfer tokens to rand from the l1 timelock
    const l1TokenTransferCallData = testErc20.interface.encodeFunctionData(
      "transfer",
      [randWallet.address, randWalletEnd]
    );

    // 2. schedule a transfer on l1
    const scheduleData = l1TimelockContract.interface.encodeFunctionData(
      "schedule",
      [
        testErc20.address,
        0,
        l1TokenTransferCallData,
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
      l2TokenContract,
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
      ).toString();
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
      testErc20.address,
      BigNumber.from(0),
      l1TokenTransferCallData,
      proposalString,
      l1ProposalSuccess,
      false
    );
  }).timeout(360000);

  it("L2-L1-L2 proposal", async function () {
    const { l1Signer, l2Signer, l1Deployer, l2Deployer } = await testSetup();
    // CHRIS: TODO: move these into test setup if we need them
    await fundL1(l1Signer, parseEther("1"));
    await fundL2(l2Signer, parseEther("1"));

    const {
      l2TokenContract,
      l2TimelockContract,
      l1TimelockContract,
      l2GovernorContract,
    } = await deployGovernance(l1Deployer, l2Deployer, l2Signer);
    // give some tokens to the governor contract
    const l2ForwarderBalanceStart = 13;
    const l2ForwarderBalanceEnd = 3;
    const randWalletEnd = l2ForwarderBalanceStart - l2ForwarderBalanceEnd;
    const randWallet = Wallet.createRandom();

    // create an l2 forwarder, who's owner is the l1 timelock
    const addr = new Address(l1TimelockContract.address);
    const l1TimelockAlias = addr.applyAlias().value;
    const forwarder = await (
      await new Forwarder__factory(l2Deployer).deploy(l1TimelockAlias)
    ).deployed();

    // send some tokens to the forwarder
    await (
      await l2TokenContract.transfer(forwarder.address, l2ForwarderBalanceStart)
    ).wait();
    expect(
      (await l2TokenContract.balanceOf(forwarder.address)).toNumber(),
      "Timelock balance start"
    ).to.eq(l2ForwarderBalanceStart);

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

    const l2TokenTransferCallData =
      l2TokenContract.interface.encodeFunctionData("transfer", [
        randWallet.address,
        randWalletEnd,
      ]);

    // 1. a
    const forwardData = forwarder.interface.encodeFunctionData("forward", [
      l2TokenContract.address,
      0,
      l2TokenTransferCallData,
      // CHRIS: TODO: this should be created by the l1 timelock? or should be previous
      id(proposalString),
    ]);

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

    // 2. schedule a transfer on l1
    const scheduleData = l1TimelockContract.interface.encodeFunctionData(
      "schedule",
      [
        l2Network.ethBridge.inbox,
        0,
        forwardData,
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
      l2TokenContract,
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

    // it should be non zero at the end
    const l1ProposalSuccess = async () => {
      return true;
    };

    console.log("before l1 component exec")
    const l1Rec = new L1TransactionReceipt(await execL1Component(
      l1Deployer,
      l2Deployer,
      l1Signer,
      l2Signer,
      l1TimelockContract,
      l2Transaction,
      l2Network.ethBridge.inbox,
      BigNumber.from(0),
      forwardData,
      proposalString,
      l1ProposalSuccess,
      true
    ));

    console.log("after l1 component exec")

    const messages = await l1Rec.getL1ToL2Messages(l2Deployer.provider!);
    console.log("before wait for status")
    const status = await messages[0].waitForStatus()
    console.log("after wait for status")
    if(status.status === L1ToL2MessageStatus.REDEEMED) {
      console.log("success", status.l2TxReceipt)
    } else {
      console.log("fail", status)
    }

    

    

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

    const state = { mining: true };
    await Promise.race([
      mineUntilStop(l1Deployer, state),
      mineUntilStop(l2Deployer, state),
      withdrawMessage.waitUntilReadyToExecute(l2Signer.provider!),
    ]);
    state.mining = false;

    // mine the timelock blocks
    const minDelay = (await l1TimelockContract.getMinDelay()).toNumber();
    for (let index = 0; index < minDelay; index++) {
      await mineBlock(l1Deployer);
    }

    if (!crossChain) {
      // execute the proposal
      const tx = await await l1TimelockContract
        .connect(l1Signer)
        .execute(
          proposalTo,
          proposalValue,
          proposalCallData,
          constants.HashZero,
          id(proposalString)
        );

      const rec = await tx.wait();
      expect(await proposalSuccess(), "L1 proposal success").to.be.true;
      return rec;
    } else {
      const l1SignerAddr = await l1Signer.getAddress();
      const estimator = new L1ToL2MessageGasEstimator(l2Deployer.provider!);
      const funcParams = await estimator.populateFunctionParams((params) => {
        const data = l1TimelockContract.interface.encodeFunctionData(
          "executeCrossChain",
          [
            proposalTo,
            proposalValue,
            proposalCallData,
            constants.HashZero,
            id(proposalString),
            params.maxSubmissionCost,
            l1SignerAddr,
            l1SignerAddr,
            params.gasLimit,
            params.maxFeePerGas,
          ]
        );

        return {
          data,
          to: l1TimelockContract.address,
          from: l1SignerAddr,
          value: params.gasLimit
            .mul(params.maxFeePerGas)
            .add(params.maxSubmissionCost),
        };
      }, l1Deployer.provider!);

      const tx = await l1Signer.sendTransaction({
        to: funcParams.to,
        data: funcParams.data,
        value: funcParams.value,
      });

      const rec = await tx.wait();
      expect(await proposalSuccess(), "L1 proposal success").to.be.true;
      console.log(rec)
      return rec;
    }
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
