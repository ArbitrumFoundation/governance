import { Address, getL2Network } from "@arbitrum/sdk";
import { Signer, Wallet } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { testSetup } from "../test-ts/testSetup";
import {
  ArbitrumTimelock,
  ArbitrumTimelock__factory,
  FixedDelegateErc20Wallet,
  FixedDelegateErc20Wallet__factory,
  L1GovernanceFactory__factory,
  L2ArbitrumGovernor,
  L2ArbitrumGovernor__factory,
  L2ArbitrumToken,
  L2ArbitrumToken__factory,
  L2GovernanceFactory__factory,
  UpgradeExecutor,
  UpgradeExecutor__factory,
} from "../typechain-types";
import {
  DeployedEventObject as L1DeployedEventObject,
  L1GovernanceFactory,
} from "../typechain-types/src/L1GovernanceFactory";
import {
  DeployedEventObject as L2DeployedEventObject,
  L2GovernanceFactory,
} from "../typechain-types/src/L2GovernanceFactory";
import * as GovernanceConstants from "./governance.constants";

/**
 * Performs each step of the Arbitrum governance deployment process
 * @returns 
 */
const deployGovernance = async (): Promise<ArbitrumTimelock> => {
  console.log("Get deployers and signers");
  const { l2Deployer, l2Signer, l1Deployer } = await testSetup();

  console.log("Deploy L1 logic contracts");
  const l1UpgradeExecutorLogic = await deployL1LogicContracts(l1Deployer);

  console.log("Deploy L2 logic contracts");
  const { timelockLogic, governorLogic, fixedDelegateLogic, l2TokenLogic, upgradeExecutor } =
    await deployL2LogicContracts(l2Deployer);

  console.log("Deploy L1 governance factory");
  const l1GovernanceFactory = await deployL1GovernanceFactory(l1Deployer);

  console.log("Deploy L2 governance factory");
  const l2GovernanceFactory = await deployL2GovernanceFactory(
    l2Deployer,
    timelockLogic,
    governorLogic,
    fixedDelegateLogic,
    l2TokenLogic,
    upgradeExecutor
  );

  // step 1
  console.log("Deploy and init L2 governance");
  const l2DeployResult = await deployL2Governance(l2Signer, l2GovernanceFactory);

  // step 2
  console.log("Deploy and init L1 governance");
  const l1DeployResult = await deployL1Governance(
    l2Deployer,
    l1GovernanceFactory,
    l1UpgradeExecutorLogic,
    l2DeployResult
  );

  // step 3
  console.log("Set executor roles");
  await setExecutorRoles(l1DeployResult, l2GovernanceFactory);

  return timelockLogic;
};

async function deployL1LogicContracts(l1Deployer: Signer) {
  const l1UpgradeExecutorLogic = await new UpgradeExecutor__factory(l1Deployer).deploy();
  return l1UpgradeExecutorLogic;
}

async function deployL2LogicContracts(l2Deployer: Signer) {
  const timelockLogic = await new ArbitrumTimelock__factory(l2Deployer).deploy();
  const governorLogic = await new L2ArbitrumGovernor__factory(l2Deployer).deploy();
  const fixedDelegateLogic = await new FixedDelegateErc20Wallet__factory(l2Deployer).deploy();
  const l2TokenLogic = await new L2ArbitrumToken__factory(l2Deployer).deploy();
  const upgradeExecutor = await new UpgradeExecutor__factory(l2Deployer).deploy();
  return { timelockLogic, governorLogic, fixedDelegateLogic, l2TokenLogic, upgradeExecutor };
}

async function deployL1GovernanceFactory(l1Deployer: Signer) {
  const l1GovernanceFactory = await new L1GovernanceFactory__factory(l1Deployer).deploy();
  return l1GovernanceFactory;
}

async function deployL2GovernanceFactory(
  l2Deployer: Signer,
  timelockLogic: ArbitrumTimelock,
  governorLogic: L2ArbitrumGovernor,
  fixedDelegateLogic: FixedDelegateErc20Wallet,
  l2TokenLogic: L2ArbitrumToken,
  upgradeExecutor: UpgradeExecutor
) {
  const l2GovernanceFactory = await new L2GovernanceFactory__factory(l2Deployer).deploy(
    timelockLogic.address,
    governorLogic.address,
    timelockLogic.address,
    fixedDelegateLogic.address,
    governorLogic.address,
    l2TokenLogic.address,
    upgradeExecutor.address
  );
  return l2GovernanceFactory;
}

async function deployL2Governance(l2Signer: Signer, l2GovernanceFactory: L2GovernanceFactory) {
  const l1TokenAddress = "0x0000000000000000000000000000000000000001";
  const initialSupply = parseEther("1");
  const l2SignerAddr = await l2Signer.getAddress();

  const l2GovDeployReceipt = await (
    await l2GovernanceFactory.deployStep1(
      {
        _l2MinTimelockDelay: GovernanceConstants.L2_TIMELOCK_DELAY,
        _l2TokenInitialSupply: initialSupply,
        _upgradeProposer: GovernanceConstants.L2_7_OF_12_SECURITY_COUNCIL,
        _coreQuorumThreshold: GovernanceConstants.L2_CORE_QUORUM_TRESHOLD,
        _l1Token: l1TokenAddress,
        _treasuryQuorumThreshold: GovernanceConstants.L2_TREASURY_QUORUM_TRESHOLD,
        _proposalThreshold: GovernanceConstants.L2_PROPOSAL_TRESHOLD,
        _votingDelay: GovernanceConstants.L2_VOTING_DELAY,
        _votingPeriod: GovernanceConstants.L2_VOTING_PERIOD,
        _minPeriodAfterQuorum: GovernanceConstants.L2_MIN_PERIOD_AFTER_QUORUM,
        _l2InitialSupplyRecipient: l2SignerAddr,
      },

      { gasLimit: 30000000 }
    )
  ).wait();

  const l2DeployResult = l2GovDeployReceipt.events?.filter(
    (e) => e.topics[0] === l2GovernanceFactory.interface.getEventTopic("Deployed")
  )[0].args as unknown as L2DeployedEventObject;
  return l2DeployResult;
}

async function deployL1Governance(
  l2Deployer: Signer,
  l1GovernanceFactory: L1GovernanceFactory,
  l1UpgradeExecutorLogic: UpgradeExecutor,
  l2DeployResult: L2DeployedEventObject
) {
  const l2Network = await getL2Network(l2Deployer);
  const l1GovDeployReceipt = await (
    await l1GovernanceFactory.deployStep2(
      l1UpgradeExecutorLogic.address,
      GovernanceConstants.L1_TIMELOCK_DELAY,
      l2Network.ethBridge.inbox,
      l2DeployResult.coreTimelock,
      GovernanceConstants.L1_9_OF_12_SECURITY_COUNCIL
    )
  ).wait();

  const l1DeployResult = l1GovDeployReceipt.events?.filter(
    (e) => e.topics[0] === l1GovernanceFactory.interface.getEventTopic("Deployed")
  )[0].args as unknown as L1DeployedEventObject;
  return l1DeployResult;
}

async function setExecutorRoles(
  l1DeployResult: L1DeployedEventObject,
  l2GovernanceFactory: L2GovernanceFactory
) {
  const l1TimelockAddress = new Address(l1DeployResult.timelock);
  const l1TimelockAliased = l1TimelockAddress.applyAlias().value;
  await l2GovernanceFactory.deployStep3([
    l1TimelockAliased,
    GovernanceConstants.L2_9_OF_12_SECURITY_COUNCIL,
  ]);
}

async function main() {
  console.log("Start governance deployment process...");
  const timelock = await deployGovernance();
  console.log("Deployment finished!");

  const verificationSuccess = await verifyDeployment(timelock.address);
  if (!verificationSuccess) {
    throw new Error("Deployment verification failed");
  }
  console.log("Verification successful!");
}

const verifyDeployment = async (timelockLogic: string): Promise<Boolean> => {
  const { l2Deployer } = await testSetup();

  let code = await l2Deployer.provider?.getCode(timelockLogic);
  if (code == "0x") {
    return false;
  }

  return true;
};

main()
  .then(() => console.log("Done."))
  .catch(console.error);
