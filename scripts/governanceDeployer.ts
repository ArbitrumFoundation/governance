import { Address, getL2Network } from "@arbitrum/sdk";
import { Signer, Wallet } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { fundL1, fundL2, testSetup } from "../test-ts/testSetup";
import {
  ArbitrumTimelock,
  ArbitrumTimelock__factory,
  FixedDelegateErc20Wallet,
  FixedDelegateErc20Wallet__factory,
  L1ArbitrumToken__factory,
  L1GovernanceFactory__factory,
  L2ArbitrumGovernor,
  L2ArbitrumGovernor__factory,
  L2ArbitrumToken,
  L2ArbitrumToken__factory,
  L2GovernanceFactory__factory,
  TransparentUpgradeableProxy,
  TransparentUpgradeableProxy__factory,
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
export const deployGovernance = async (): Promise<ArbitrumTimelock> => {
  // test version of deployers/signers (TODO - pull those from .env)
  console.log("Get deployers and signers");
  const { l2Deployer, l2Signer, l1Deployer, l1Signer } = await testSetup();
  await fundL1(l1Signer, parseEther("1"));
  await fundL2(l2Signer, parseEther("1"));

  console.log("Deploy L1 logic contracts");
  const l1UpgradeExecutorLogic = await deployL1LogicContracts(l1Deployer);

  console.log("Deploy L2 logic contracts");
  const { timelockLogic, governorLogic, fixedDelegateLogic, l2TokenLogic, upgradeExecutor } =
    await deployL2LogicContracts(l2Deployer);

  console.log("Deploy L1 governance factory");
  const l1GovernanceFactory = await deployL1GovernanceFactory(l1Deployer);

  console.log("Deploy and init L1 Arbitrum token");
  const { l1Token, l1TokenProxy } = await deployAndInitL1Token(l1Deployer, l1Signer);

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
  const l2DeployResult = await deployL2Governance(l2Signer, l2GovernanceFactory, l1Token.address);

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

  // post deployment
  console.log("Execute post deployment tasks");
  await postDeploymentTasks(l1TokenProxy, l1DeployResult, l2Signer, l2DeployResult);

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

async function deployAndInitL1Token(l1Deployer: Signer, l1Signer: Signer) {
  // deploy logic
  const l1TokenLogic = await new L1ArbitrumToken__factory(l1Deployer).deploy();

  // deploy proxy
  const l1TokenProxy = await new TransparentUpgradeableProxy__factory(l1Deployer).deploy(
    l1TokenLogic.address,
    l1Deployer.getAddress(),
    "0x",
    { gasLimit: 3000000 }
  );

  // initialize token
  const l1Token = L1ArbitrumToken__factory.connect(l1TokenProxy.address, l1Deployer.provider!);
  await (
    await l1Token
      .connect(l1Signer)
      .initialize(
        GovernanceConstants.L1_ARB_ROUTER,
        GovernanceConstants.L1_ARB_GATEWAY,
        GovernanceConstants.L1_NOVA_ROUTER,
        GovernanceConstants.L1_NOVA_GATEWAY
      )
  ).wait();

  ////
  //TODO register token on L2
  ////

  return { l1Token, l1TokenProxy };
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

async function deployL2Governance(
  l2Signer: Signer,
  l2GovernanceFactory: L2GovernanceFactory,
  l1TokenAddress: string
) {
  const l2SignerAddr = await l2Signer.getAddress();

  const l2GovDeployReceipt = await (
    await l2GovernanceFactory.deployStep1(
      {
        _l2MinTimelockDelay: GovernanceConstants.L2_TIMELOCK_DELAY,
        _l2TokenInitialSupply: parseEther(GovernanceConstants.L2_TOKEN_INITIAL_SUPPLY),
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

async function postDeploymentTasks(
  l1TokenProxy: TransparentUpgradeableProxy,
  l1DeployResult: L1DeployedEventObject,
  l2Signer: Signer,
  l2DeployResult: L2DeployedEventObject
) {
  // set L1 proxy admin as L1 token's admin
  await l1TokenProxy.changeAdmin(l1DeployResult.proxyAdmin);

  // transfer L2 token ownership to upgradeExecutor
  const l2Token = L2ArbitrumToken__factory.connect(l2DeployResult.token, l2Signer.provider!);
  await l2Token.connect(l2Signer).transferOwnership(l2DeployResult.executor);

  // transfer tokens from _l2InitialSupplyRecipient to the treasury
  await l2Token
    .connect(l2Signer)
    .transfer(l2DeployResult.treasuryTimelock, GovernanceConstants.L2_NUM_OF_TOKENS_FOR_TREASURY);

  // transfer tokens from _l2InitialSupplyRecipient to the token distributor
  await l2Token
    .connect(l2Signer)
    .transfer(
      GovernanceConstants.L2_TOKEN_DISTRIBUTOR_CONTRACT,
      GovernanceConstants.L2_NUM_OF_TOKENS_FOR_TOKEN_DISTRIBUTOR
    );
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
