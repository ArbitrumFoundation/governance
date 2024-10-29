import { Address, getL2Network } from "@arbitrum/sdk";
import { ArbitrumProvider } from "@arbitrum/sdk/dist/lib/utils/arbProvider";
import { JsonRpcProvider, Provider } from "@ethersproject/providers";
import { expect } from "chai";
import { Signer, Wallet, constants } from "ethers";
import { parseEther } from "ethers/lib/utils";
import {
  ArbitrumTimelock__factory,
  FixedDelegateErc20Wallet__factory,
  L1ArbitrumTimelock__factory,
  L1GovernanceFactory__factory,
  L2ArbitrumGovernor__factory,
  L2ArbitrumToken__factory,
  L2GovernanceFactory__factory,
  ProxyAdmin__factory,
  UpgradeExecutor__factory,
} from "../typechain-types";
import { DeployedEventObject as L1DeployedEventObject } from "../typechain-types/src/L1GovernanceFactory";
import { DeployedEventObject as L2DeployedEventObject } from "../typechain-types/src/L2GovernanceFactory";
import {
  l2L1L2MonitoringTest,
  l2L1L2MonitoringValueTest,
  l2L1MonitoringTest,
  l2L1MonitoringValueTest,
  l2L1ProposalTest,
  l2l1l2Proposal,
} from "./integration";
import { fundL1, fundL2, testSetup } from "./testSetup";

const wait = async (ms: number) => new Promise((res) => setTimeout(res, ms));

const mineBlock = async (signer: Signer) => {
  await (await signer.sendTransaction({ to: await signer.getAddress(), value: 0 })).wait();
};

describe("Governor", function () {
  const randomFundedWallets = async (l1Provider: Provider, l2Provider: Provider) => {
    const seed = Wallet.createRandom();
    const l1Signer = seed.connect(l1Provider);

    const seed2 = Wallet.createRandom();
    const l2Signer = seed2.connect(l2Provider);

    await fundL1(l1Signer, parseEther("1"));
    await fundL2(l2Signer, parseEther("1"));

    return { l1Signer, l2Signer };
  };

  const deployGovernance = async (l1Deployer: Signer, l2Deployer: Signer, l2Signer: Signer) => {
    const initialSupply = parseEther("1");
    const l1TimeLockDelay = 5;
    const l2TimeLockDelay = 7;
    const l2SignerAddr = await l2Signer.getAddress();
    // we use a non zero dummy address for the l1 token
    // it doesnt exist yet but we plan to upgrade the l2 token contract add this address
    const l1TokenAddress = "0x0000000000000000000000000000000000000001";
    const arbDaoConstitutionHash =
      "0x0000000000000000000000000000000000000000000000000000000000000001";

    const sevenSecurityCouncil = Wallet.createRandom();
    const nineTwelthSecurityCouncil = Wallet.createRandom();

    const timelockLogic = await new ArbitrumTimelock__factory(l2Deployer).deploy();
    const governorLogic = await new L2ArbitrumGovernor__factory(l2Deployer).deploy();
    const fixedDelegateLogic = await new FixedDelegateErc20Wallet__factory(l2Deployer).deploy();
    const l2TokenLogic = await new L2ArbitrumToken__factory(l2Deployer).deploy();
    const upgradeExecutor = await new UpgradeExecutor__factory(l2Deployer).deploy();

    // deploy L2
    const l2GovernanceFac = await new L2GovernanceFactory__factory(l2Deployer).deploy(
      timelockLogic.address,
      governorLogic.address,
      timelockLogic.address,
      fixedDelegateLogic.address,
      governorLogic.address,
      l2TokenLogic.address,
      upgradeExecutor.address
    );
    const l2GovDeployReceipt = await (
      await l2GovernanceFac.deployStep1(
        {
          _l2MinTimelockDelay: l2TimeLockDelay,
          _l2TokenInitialSupply: initialSupply,
          _l2NonEmergencySecurityCouncil: sevenSecurityCouncil.address,
          _coreQuorumThreshold: 5,
          _l1Token: l1TokenAddress,
          _treasuryQuorumThreshold: 3,
          _proposalThreshold: 100,
          _votingDelay: 10,
          _votingPeriod: 10,
          _minPeriodAfterQuorum: 1,
          _l2InitialSupplyRecipient: l2SignerAddr,
          _l2EmergencySecurityCouncil: nineTwelthSecurityCouncil.address,
          _constitutionHash: arbDaoConstitutionHash,
          _l2TreasuryMinTimelockDelay: l2TimeLockDelay,
        },

        { gasLimit: 30000000 }
      )
    ).wait();

    const l2DeployResult = l2GovDeployReceipt.events?.filter(
      (e) => e.topics[0] === l2GovernanceFac.interface.getEventTopic("Deployed")
    )[0].args as unknown as L2DeployedEventObject;

    // deploy L1
    const l1SecurityCouncil = Wallet.createRandom();
    const l2Network = await getL2Network(l2Deployer);
    const l1UpgradeExecutorLogic = await new UpgradeExecutor__factory(l1Deployer).deploy();
    const l1GovernanceFac = await new L1GovernanceFactory__factory(l1Deployer).deploy();
    const l1GovDeployReceipt = await (
      await l1GovernanceFac.deployStep2(
        l1UpgradeExecutorLogic.address,
        l1TimeLockDelay,
        l2Network.ethBridge.inbox,
        l2DeployResult.coreTimelock,
        l1SecurityCouncil.address
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
    const aliasedL1Timelock = l1TimelockAddress.applyAlias().value;
    await l2GovernanceFac.deployStep3(aliasedL1Timelock);

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
    await (await l2TokenContract.connect(l2Signer).delegate(l2SignerAddr)).wait();
    expect(
      await l2TokenContract.callStatic.delegates(l2SignerAddr),
      "L2 signer delegate after"
    ).to.eq(l2SignerAddr);

    // mine some blocks to ensure that the votes are available for the previous block
    // make sure to mine at least 2 l1 block
    const arbProvider = new ArbitrumProvider(l2Deployer.provider! as JsonRpcProvider);
    const blockStart = await arbProvider.getBlock("latest");
    while (true) {
      const blockNext = await arbProvider.getBlock("latest");
      await wait(1000);
      await mineBlock(l1Deployer);
      await mineBlock(l2Deployer);
      if (blockNext.l1BlockNumber - blockStart.l1BlockNumber > 5) break;
    }

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

  it("L2-L1 monitoring value", async () => {
    const { l1Signer, l2Signer, l1Deployer, l2Deployer } = await testSetup();
    await fundL1(l1Signer, parseEther("1"));
    await fundL2(l2Signer, parseEther("1"));
    const localMiners = await randomFundedWallets(l1Deployer.provider!, l2Deployer.provider!);

    const { l1TimelockContract, l2GovernorContract, l1UpgradeExecutor } = await deployGovernance(
      l1Deployer,
      l2Deployer,
      l2Signer
    );

    await l2L1MonitoringValueTest(
      l1Signer,
      l2Signer,
      l2Signer,
      l1UpgradeExecutor,
      l1TimelockContract,
      l2GovernorContract,
      localMiners
    );
  }).timeout(600000);

  it("L2-L1-L2 monitoring value", async () => {
    const { l1Signer, l2Signer, l1Deployer, l2Deployer } = await testSetup();
    await fundL1(l1Signer, parseEther("1"));
    await fundL2(l2Signer, parseEther("1"));
    const localMiners = await randomFundedWallets(l1Deployer.provider!, l2Deployer.provider!);

    const { l1TimelockContract, l2GovernorContract, l2UpgradeExecutor } = await deployGovernance(
      l1Deployer,
      l2Deployer,
      l2Signer
    );

    await l2L1L2MonitoringValueTest(
      l1Signer,
      l2Signer,
      l2Signer,
      l2UpgradeExecutor,
      l1TimelockContract,
      l2GovernorContract,
      localMiners
    );
  }).timeout(600000);

  it("L2-L1 monitoring", async () => {
    const { l1Signer, l2Signer, l1Deployer, l2Deployer } = await testSetup();
    await fundL1(l1Signer, parseEther("1"));
    await fundL2(l2Signer, parseEther("1"));
    const localMiners = await randomFundedWallets(l1Deployer.provider!, l2Deployer.provider!);

    const { l1TimelockContract, l2GovernorContract, l1UpgradeExecutor } = await deployGovernance(
      l1Deployer,
      l2Deployer,
      l2Signer
    );

    await l2L1MonitoringTest(
      l1Signer,
      l2Signer,
      l2Signer,
      l1UpgradeExecutor,
      l1TimelockContract,
      l2GovernorContract,
      localMiners
    );
  }).timeout(600000);

  it("L2-L1-L2 monitoring", async () => {
    const { l1Signer, l2Signer, l1Deployer, l2Deployer } = await testSetup();
    await fundL1(l1Signer, parseEther("1"));
    await fundL2(l2Signer, parseEther("1"));
    const localMiners = await randomFundedWallets(l1Deployer.provider!, l2Deployer.provider!);

    const { l1TimelockContract, l2GovernorContract, l2UpgradeExecutor } = await deployGovernance(
      l1Deployer,
      l2Deployer,
      l2Signer
    );

    await l2L1L2MonitoringTest(
      l1Signer,
      l2Signer,
      l2Signer,
      l2UpgradeExecutor,
      l1TimelockContract,
      l2GovernorContract,
      localMiners
    );
  }).timeout(600000);

  it("L2-L1 proposal", async () => {
    const { l1Signer, l2Signer, l1Deployer, l2Deployer } = await testSetup();
    await fundL1(l1Signer, parseEther("1"));
    await fundL2(l2Signer, parseEther("1"));

    const { l2TimelockContract, l1TimelockContract, l2GovernorContract, l1UpgradeExecutor } =
      await deployGovernance(l1Deployer, l2Deployer, l2Signer);
    // give some tokens to the governor contract

    await l2L1ProposalTest(
      l1Signer,
      l2Signer,
      l1Deployer,
      l2Deployer,
      l1UpgradeExecutor,
      l2GovernorContract,
      l1TimelockContract,
      l2TimelockContract,
    );
  }).timeout(600000);

  it("L2-L1-L2 proposal", async () => {
    const { l1Signer, l2Signer, l1Deployer, l2Deployer } = await testSetup();
    await fundL1(l1Signer, parseEther("1"));
    await fundL2(l2Signer, parseEther("1"));

    const { l2TimelockContract, l1TimelockContract, l2GovernorContract, l2UpgradeExecutor } =
      await deployGovernance(l1Deployer, l2Deployer, l2Signer);

    await l2l1l2Proposal(
      l1Signer,
      l2Signer,
      l1Deployer,
      l2Deployer,
      l2GovernorContract,
      l1TimelockContract,
      l2TimelockContract,
      l2UpgradeExecutor
    );
  }).timeout(600000);
});
