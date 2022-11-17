import { Address, getL2Network } from "@arbitrum/sdk";
import { Wallet } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { testSetup } from "../test-ts/testSetup";
import {
  ArbitrumTimelock,
  ArbitrumTimelock__factory,
  FixedDelegateErc20Wallet__factory,
  L1GovernanceFactory__factory,
  L2ArbitrumGovernor__factory,
  L2ArbitrumToken__factory,
  L2GovernanceFactory__factory,
  UpgradeExecutor__factory,
} from "../typechain-types";
import { DeployedEventObject as L1DeployedEventObject } from "../typechain-types/src/L1GovernanceFactory";
import { DeployedEventObject as L2DeployedEventObject } from "../typechain-types/src/L2GovernanceFactory";
import * as GovernanceConstants from "./governance.constants";

const deployGovernance = async (): Promise<ArbitrumTimelock> => {
  console.log("Get deployers and signers");
  const { l2Deployer, l2Signer, l1Deployer } = await testSetup();

  console.log("Deploy L1 logic contracts");
  const l1UpgradeExecutorLogic = await new UpgradeExecutor__factory(l1Deployer).deploy();

  console.log("Deploy L2 logic contracts");
  const timelockLogic = await new ArbitrumTimelock__factory(l2Deployer).deploy();
  const governorLogic = await new L2ArbitrumGovernor__factory(l2Deployer).deploy();
  const fixedDelegateLogic = await new FixedDelegateErc20Wallet__factory(l2Deployer).deploy();
  const l2TokenLogic = await new L2ArbitrumToken__factory(l2Deployer).deploy();
  const upgradeExecutor = await new UpgradeExecutor__factory(l2Deployer).deploy();

  // step 1
  console.log("Deploy and init L2 governance");
  const l2GovernanceFactory = await new L2GovernanceFactory__factory(l2Deployer).deploy(
    timelockLogic.address,
    governorLogic.address,
    timelockLogic.address,
    fixedDelegateLogic.address,
    governorLogic.address,
    l2TokenLogic.address,
    upgradeExecutor.address
  );

  const initialSupply = parseEther("1");
  const l2SignerAddr = await l2Signer.getAddress();
  const l1TokenAddress = "0x0000000000000000000000000000000000000001";

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

  // step 2
  console.log("Deploy and init L1 governance");
  const l2Network = await getL2Network(l2Deployer);
  const l1GovernanceFactory = await new L1GovernanceFactory__factory(l1Deployer).deploy();

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

  // step 3
  console.log("Set executor roles");
  const l1TimelockAddress = new Address(l1DeployResult.timelock);
  const l1TimelockAliased = l1TimelockAddress.applyAlias().value;
  await l2GovernanceFactory.deployStep3([
    l1TimelockAliased,
    GovernanceConstants.L2_9_OF_12_SECURITY_COUNCIL,
  ]);

  return timelockLogic;
};

const verifyDeployment = async (timelockLogic: string): Promise<Boolean> => {
  const { l2Deployer } = await testSetup();

  let code = await l2Deployer.provider?.getCode(timelockLogic);
  if (code == "0x") {
    return false;
  }

  return true;
};

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

main()
  .then(() => console.log("Done."))
  .catch(console.error);
