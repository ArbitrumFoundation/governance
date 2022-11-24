import { Address } from "@arbitrum/sdk";
import { ethers, Signer } from "ethers";
import { parseEther } from "ethers/lib/utils";
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
  ProxyAdmin,
  ProxyAdmin__factory,
  TokenDistributor__factory,
  TransparentUpgradeableProxy,
  TransparentUpgradeableProxy__factory,
  UpgradeExecutor,
  UpgradeExecutor__factory,
} from "../typechain-types";
import { L2CustomGatewayToken__factory } from "../typechain-types-imported/index";
import {
  DeployedEventObject as L1DeployedEventObject,
  L1GovernanceFactory,
} from "../typechain-types/src/L1GovernanceFactory";
import {
  DeployedEventObject as L2DeployedEventObject,
  L2GovernanceFactory,
} from "../typechain-types/src/L2GovernanceFactory";
import * as GovernanceConstants from "./governance.constants";
import { getDeployers } from "./providerSetup";

/**
 * Performs each step of the Arbitrum governance deployment process.
 *
 * /// @notice Governance Deployment Steps:
 * /// 1. Deploy the following pre-requiste logic contracts:
 * ///     L1:
 * ///         - UpgradeExecutor logic
 * ///     L2:
 * ///         - ArbitrumTimelock logic
 * ///         - L2ArbitrumGovernor logic
 * ///         - FixedDelegateErc20 logic
 * ///         - L2ArbitrumToken logic
 * ///         - UpgradeExecutor logic
 * /// 2. Then deploy the following (in any order):
 * ///     L1:
 * ///         - L1GoveranceFactory
 * ///         - L1Token
 * ///         - Gnosis Safe Multisig 9 of 12 Security Council
 * ///     L2:
 * ///         - L2GovernanceFactory
 * ///         - Gnosis Safe Multisig 9 of 12 Security Council
 * ///         - Gnosis Safe Multisig 7 of 12 Security Council
 * ///
 * ///     L1GoveranceFactory and L2GovernanceFactory deployers will be their respective owners, and will carry out the following steps.
 * /// 3. Call L2GovernanceFactory.deployStep1
 * ///     - Dependencies: L1-Token address, 7 of 12 multisig (as _upgradeProposer)
 * ///
 * /// 4. Call L1GoveranceFactory.deployStep2
 * ///     - Dependencies: L1 security council address, L2 Timelock address (deployed in previous step)
 * ///
 * /// 5. Call L2GovernanceFactory.deployStep3
 * ///     - Dependencies: (Aliased) L1-timelock address (deployed in previous step), L2 security council address (as _l2UpgradeExecutors)
 * /// 6. From the _l2InitialSupplyRecipient transfer ownership of the L2ArbitrumToken to the UpgradeExecutor
 * ///    Then transfer tokens from _l2InitialSupplyRecipient to the treasury and other token distributor
 * @returns
 */
export const deployGovernance = async () => {
  console.log("Get deployers and signers");
  const { ethDeployer, arbDeployer, arbInitialSupplyRecipient, novaDeployer } =
    await getDeployers();

  console.log("Deploy L1 logic contracts");
  const l1UpgradeExecutorLogic = await deployL1LogicContracts(ethDeployer);

  console.log("Deploy L2 logic contracts");
  const { timelockLogic, governorLogic, fixedDelegateLogic, l2TokenLogic, upgradeExecutor } =
    await deployL2LogicContracts(arbDeployer);

  console.log("Deploy L1 governance factory");
  const l1GovernanceFactory = await deployL1GovernanceFactory(ethDeployer);

  console.log("Deploy and init L1 Arbitrum token");
  const { l1Token, l1TokenProxy } = await deployAndInitL1Token(ethDeployer);

  console.log("Deploy L2 governance factory");
  const l2GovernanceFactory = await deployL2GovernanceFactory(
    arbDeployer,
    timelockLogic,
    governorLogic,
    fixedDelegateLogic,
    l2TokenLogic,
    upgradeExecutor
  );

  console.log("Deploy UpgradeExecutor to Nova");
  const novaProxyAdmin = await deployNovaUpgradeExecutor(novaDeployer);

  console.log("Deploy token to Nova");
  const novaToken = await deployTokenToNova(novaDeployer, novaProxyAdmin);

  // step 1
  console.log("Init L2 governance");
  const l2DeployResult = await initL2Governance(
    arbInitialSupplyRecipient,
    l2GovernanceFactory,
    l1Token.address
  );

  // step 2
  console.log("Init L1 governance");
  const l1DeployResult = await initL1Governance(
    l1GovernanceFactory,
    l1UpgradeExecutorLogic,
    l2DeployResult
  );

  // step 3
  console.log("Set executor roles");
  await setExecutorRoles(l1DeployResult, l2GovernanceFactory);

  // deploy ARB distributor
  console.log("Deploy TokenDistributor");
  await deployTokenDistributor(arbDeployer, l2DeployResult);

  console.log("Post deployment L1 token tasks");
  await postDeploymentL1TokenTasks(
    ethDeployer,
    l1TokenProxy,
    l1DeployResult.proxyAdmin,
    l2DeployResult.token,
    novaToken.address
  );

  console.log("Post deployment L2 token tasks");
  await postDeploymentL2TokenTasks(arbInitialSupplyRecipient, l2DeployResult);
};

async function deployL1LogicContracts(ethDeployer: Signer) {
  const l1UpgradeExecutorLogic = await new UpgradeExecutor__factory(ethDeployer).deploy();
  return l1UpgradeExecutorLogic;
}

async function deployL2LogicContracts(arbDeployer: Signer) {
  const timelockLogic = await new ArbitrumTimelock__factory(arbDeployer).deploy();
  const governorLogic = await new L2ArbitrumGovernor__factory(arbDeployer).deploy();
  const fixedDelegateLogic = await new FixedDelegateErc20Wallet__factory(arbDeployer).deploy();
  const l2TokenLogic = await new L2ArbitrumToken__factory(arbDeployer).deploy();
  const upgradeExecutor = await new UpgradeExecutor__factory(arbDeployer).deploy();
  return { timelockLogic, governorLogic, fixedDelegateLogic, l2TokenLogic, upgradeExecutor };
}

async function deployL1GovernanceFactory(ethDeployer: Signer) {
  const l1GovernanceFactory = await new L1GovernanceFactory__factory(ethDeployer).deploy();
  await l1GovernanceFactory.deployed();
  return l1GovernanceFactory;
}

async function deployAndInitL1Token(ethDeployer: Signer) {
  // deploy logic
  const l1TokenLogic = await new L1ArbitrumToken__factory(ethDeployer).deploy();
  await l1TokenLogic.deployed();

  // deploy proxy
  const l1TokenProxy = await new TransparentUpgradeableProxy__factory(ethDeployer).deploy(
    l1TokenLogic.address,
    ethDeployer.getAddress(),
    "0x",
    { gasLimit: 3000000 }
  );
  await l1TokenProxy.deployed();

  const l1Token = L1ArbitrumToken__factory.connect(l1TokenProxy.address, ethDeployer);

  return { l1Token, l1TokenProxy };
}

async function deployL2GovernanceFactory(
  arbDeployer: Signer,
  timelockLogic: ArbitrumTimelock,
  governorLogic: L2ArbitrumGovernor,
  fixedDelegateLogic: FixedDelegateErc20Wallet,
  l2TokenLogic: L2ArbitrumToken,
  upgradeExecutor: UpgradeExecutor
) {
  const l2GovernanceFactory = await new L2GovernanceFactory__factory(arbDeployer).deploy(
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

async function deployNovaUpgradeExecutor(novaDeployer: Signer) {
  // deploy proxy admin
  const novaProxyAdmin = await new ProxyAdmin__factory(novaDeployer).deploy();
  await novaProxyAdmin.deployed();

  // deploy logic
  const novaUpgradeExecutorLogic = await new UpgradeExecutor__factory(novaDeployer).deploy();
  await novaUpgradeExecutorLogic.deployed();

  // deploy proxy with proxyAdmin as owner
  const novaUpgradeExecutorProxy = await new TransparentUpgradeableProxy__factory(
    novaDeployer
  ).deploy(novaUpgradeExecutorLogic.address, novaProxyAdmin.address, "0x");
  await novaUpgradeExecutorProxy.deployed();

  // init executor
  const novaUpgradeExecutor = UpgradeExecutor__factory.connect(
    novaUpgradeExecutorProxy.address,
    novaDeployer
  );
  await novaUpgradeExecutor.initialize(novaUpgradeExecutor.address, [
    GovernanceConstants.NOVA_9_OF_12_SECURITY_COUNCIL,
  ]);

  // transfer ownership over novaProxyAdmin to executor
  await novaProxyAdmin.transferOwnership(novaUpgradeExecutor.address);

  return novaProxyAdmin;
}

async function deployTokenToNova(novaDeployer: Signer, proxyAdmin: ProxyAdmin) {
  // deploy token logic
  const novaTokenLogic = await new L2CustomGatewayToken__factory(novaDeployer).deploy();
  await novaTokenLogic.deployed();

  // deploy token proxy
  const novaTokenProxy = await new TransparentUpgradeableProxy__factory(novaDeployer).deploy(
    novaTokenLogic.address,
    proxyAdmin.address,
    "0x"
  );
  await novaTokenProxy.deployed();

  // init
  const novaToken = L2CustomGatewayToken__factory.connect(novaTokenProxy.address, novaDeployer);
  await novaToken.initialize(
    GovernanceConstants.NOVA_TOKEN_NAME,
    GovernanceConstants.NOVA_TOKEN_SYMBOL,
    GovernanceConstants.NOVA_TOKEN_DECIMALS,
    GovernanceConstants.NOVA_TOKEN_GATEWAY,
    GovernanceConstants.L1_NOVA_GATEWAY
  );

  return novaToken;
}

async function initL2Governance(
  arbInitialSupplyRecipient: Signer,
  l2GovernanceFactory: L2GovernanceFactory,
  l1TokenAddress: string
) {
  const arbInitialSupplyRecipientAddr = await arbInitialSupplyRecipient.getAddress();

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
        _l2InitialSupplyRecipient: arbInitialSupplyRecipientAddr,
      },

      { gasLimit: 30000000 }
    )
  ).wait();

  const l2DeployResult = l2GovDeployReceipt.events?.filter(
    (e) => e.topics[0] === l2GovernanceFactory.interface.getEventTopic("Deployed")
  )[0].args as unknown as L2DeployedEventObject;
  return l2DeployResult;
}

async function initL1Governance(
  l1GovernanceFactory: L1GovernanceFactory,
  l1UpgradeExecutorLogic: UpgradeExecutor,
  l2DeployResult: L2DeployedEventObject
) {
  const l1GovDeployReceipt = await (
    await l1GovernanceFactory.deployStep2(
      l1UpgradeExecutorLogic.address,
      GovernanceConstants.L1_TIMELOCK_DELAY,
      GovernanceConstants.L1_ARB_INBOX,
      l2DeployResult.coreTimelock,
      GovernanceConstants.L1_9_OF_12_SECURITY_COUNCIL,
      { gasLimit: 30000000 }
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

async function postDeploymentL1TokenTasks(
  ethDeployer: Signer,
  l1TokenProxy: TransparentUpgradeableProxy,
  l1ProxyAdminAddress: string,
  l2TokenAddress: string,
  novaTokenAddress: string
) {
  // set L1 proxy admin as L1 token's admin
  await (await l1TokenProxy.changeAdmin(l1ProxyAdminAddress)).wait();

  // init L1 token
  const l1Token = L1ArbitrumToken__factory.connect(l1TokenProxy.address, ethDeployer);
  await l1Token.initialize(
    GovernanceConstants.L1_ARB_ROUTER,
    GovernanceConstants.L1_ARB_GATEWAY,
    GovernanceConstants.L1_NOVA_ROUTER,
    GovernanceConstants.L1_NOVA_GATEWAY
  );

  // register token on L2
  /// TODO - properly calculate gas parameters and value to send
  const ethDeployerAddress = await ethDeployer.getAddress();
  await l1Token.registerTokenOnL2(
    {
      l2TokenAddress: l2TokenAddress,
      maxSubmissionCostForCustomGateway: 100,
      maxSubmissionCostForRouter: 100,
      maxGasForCustomGateway: 100,
      maxGasForRouter: 100,
      gasPriceBid: 100,
      valueForGateway: 100,
      valueForRouter: 100,
      creditBackAddress: ethDeployerAddress,
    },
    {
      l2TokenAddress: novaTokenAddress,
      maxSubmissionCostForCustomGateway: 100,
      maxSubmissionCostForRouter: 100,
      maxGasForCustomGateway: 100,
      maxGasForRouter: 100,
      gasPriceBid: 100,
      valueForGateway: 100,
      valueForRouter: 100,
      creditBackAddress: ethDeployerAddress,
    },
    { value: ethers.utils.parseEther("1"), gasLimit: 3000000 }
  );
}

async function postDeploymentL2TokenTasks(
  arbInitialSupplyRecipient: Signer,
  l2DeployResult: L2DeployedEventObject
) {
  // transfer L2 token ownership to upgradeExecutor
  const l2Token = L2ArbitrumToken__factory.connect(
    l2DeployResult.token,
    arbInitialSupplyRecipient.provider!
  );
  await l2Token.connect(arbInitialSupplyRecipient).transferOwnership(l2DeployResult.executor);

  // transfer tokens from _l2InitialSupplyRecipient to the treasury
  await l2Token
    .connect(arbInitialSupplyRecipient)
    .transfer(l2DeployResult.treasuryTimelock, GovernanceConstants.L2_NUM_OF_TOKENS_FOR_TREASURY);

  // tokens should be transfered to TokenDistributor as well, but only after all recipients are correctly set.
}

async function deployTokenDistributor(arbDeployer: Signer, l2DeployResult: L2DeployedEventObject) {
  await new TokenDistributor__factory(arbDeployer).deploy(
    l2DeployResult.token,
    GovernanceConstants.L2_SWEEP_RECECIVER,
    GovernanceConstants.L2_TOKEN_DISTRIBUTOR_OWNER,
    GovernanceConstants.L2_CLAIM_PERIOD_START,
    GovernanceConstants.L2_CLAIM_PERIOD_END
  );
}

async function main() {
  console.log("Start governance deployment process...");
  await deployGovernance();
  console.log("Deployment finished!");

  const verificationSuccess = await verifyDeployment();
  if (!verificationSuccess) {
    throw new Error("Deployment verification failed");
  }
  console.log("Verification successful!");
}

const verifyDeployment = async (): Promise<Boolean> => {
  //TODO
  return true;
};

main()
  .then(() => console.log("Done."))
  .catch(console.error);
