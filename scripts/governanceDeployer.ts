import { Address, L1ToL2MessageStatus, L1TransactionReceipt } from "@arbitrum/sdk";
import { Inbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Inbox__factory";
import { L1CustomGateway__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L1CustomGateway__factory";
import { L1GatewayRouter__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L1GatewayRouter__factory";
import { L2CustomGateway__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L2CustomGateway__factory";
import { L2GatewayRouter__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L2GatewayRouter__factory";
import { BigNumber, ethers, Signer } from "ethers";
import { parseEther } from "ethers/lib/utils";
import {
  ArbitrumTimelock,
  ArbitrumTimelock__factory,
  FixedDelegateErc20Wallet,
  FixedDelegateErc20Wallet__factory,
  L1ArbitrumToken,
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
import {
  L1ForceOnlyReverseCustomGateway,
  L1ForceOnlyReverseCustomGateway__factory,
  L2CustomGatewayToken__factory,
  L2ReverseCustomGateway__factory,
} from "../typechain-types-imported/index";
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
import { getNumberOfRecipientsSet, setClaimRecipients } from "./tokenDistributorHelper";

// store address for every deployed contract
let deployedContracts: { [key: string]: string } = {};
const DEPLOYED_CONTRACTS_FILE_NAME = "deployedContracts.json";

/**
 * Performs each step of the Arbitrum governance deployment process.
 *
 * /// @notice Governance Deployment Steps:
 * /// 1. Deploy the following pre-requiste logic contracts on L1:
 * ///         - UpgradeExecutor logic
 * /// 2. Deploy the following pre-requiste logic contracts on L2:
 * ///         - ArbitrumTimelock logic
 * ///         - L2ArbitrumGovernor logic
 * ///         - FixedDelegateErc20 logic
 * ///         - L2ArbitrumToken logic
 * ///         - UpgradeExecutor logic
 * /// 3. Deploy L1 factory:
 * ///         - L1GoveranceFactory
 * /// 4. Deploy L2 factory:
 * ///         - L2GoveranceFactory
 * /// 5. Deploy and init reverse gateways (to be used for Arb token):
 * ///         - L1ForceOnlyReverseCustomGateway (logic + proxy)
 * ///         - L2ReverseCustomGateway (logic + proxy)
 * ///         - init L1 reverse gateway
 * ///         - init L2 reverse gateway
 * /// 6. Deploy and init L1 token:
 * ///         - L1ArbitrumToken (logic + proxy)
 * ///         - init L1 token
 * /// 7. Deploy Nova proxy admin and upgrade executor
 * ///         - ProxyAdmin (to Nova)
 * ///         - UpgradeExecutor (logic + proxy, to Nova)
 * /// 8. Deploy and init token on Nova
 * ///         - L2CustomGatewayToken (logic + proxy, to Nova)
 * ///         - init token
 * /// 9. Init L2 governance
 * ///         - call L2GovernanceFactory.deployStep1
 * ///         - fetch and store addresses of deployed contracts
 * /// 10. Init L1 governance
 * ///         - call L1GovernanceFactory.deployStep2
 * ///         - fetch and store addresses of deployed contracts
 * /// 11. Set executor roles
 * ///         - call l2GovernanceFactory.deployStep3
 * ///         - call novaUpgradeExecutor.initialize
 * ///         - transfer novaProxyAdmin ownership to upgrade executor
 * /// 12. Post deployment L1 tasks - token registration
 * ///         - register L1 token to ArbOne token mapping on reverse gateways
 * ///         - register L1 token to reverse gateway mapping on Arb routers
 * ///         - register L1 token to Nova token mapping on custom gateways
 * ///         - register L1 token to custom gateway token mapping on Nova routers
 * /// 13. Post deployment L2 tasks - transfer tokens
 * ///         - transfer part of tokens from arbDeployer (initial supply receiver) to treasury
 * /// 14. Deploy and init TokenDistributor
 * ///         - deploy TokenDistributor
 * ///         - transfer claimable tokens from arbDeployer to distributor
 * ///         - set claim recipients (done in batches over ~2h period)
 * ///         - if number of set recipients and total claimable amount match expected values, transfer ownership to executor
 * ///
 * /// And at the end of script execution write addresses of deployed contracts to local JSON file.
 *
 * @returns
 */
export const deployGovernance = async () => {
  console.log("Get deployers and signers");
  const { ethDeployer, arbDeployer, novaDeployer } = await getDeployers();

  console.log("Deploy L1 logic contracts");
  const l1UpgradeExecutorLogic = await deployL1LogicContracts(ethDeployer);

  console.log("Deploy L2 logic contracts");
  const { timelockLogic, governorLogic, fixedDelegateLogic, l2TokenLogic, upgradeExecutor } =
    await deployL2LogicContracts(arbDeployer);

  console.log("Deploy L1 governance factory");
  const l1GovernanceFactory = await deployL1GovernanceFactory(ethDeployer);

  console.log("Deploy L2 governance factory");
  const l2GovernanceFactory = await deployL2GovernanceFactory(
    arbDeployer,
    timelockLogic,
    governorLogic,
    fixedDelegateLogic,
    l2TokenLogic,
    upgradeExecutor
  );

  console.log("Deploy reverse gateways");
  const l1ReverseGateway = await deployReverseGateways(
    l1GovernanceFactory,
    l2GovernanceFactory,
    ethDeployer,
    arbDeployer
  );

  console.log("Deploy and init L1 Arbitrum token");
  const { l1Token } = await deployAndInitL1Token(
    l1GovernanceFactory,
    l1ReverseGateway,
    ethDeployer
  );

  console.log("Deploy UpgradeExecutor to Nova");
  const { novaProxyAdmin, novaUpgradeExecutorProxy } = await deployNovaUpgradeExecutor(
    novaDeployer
  );

  console.log("Deploy token to Nova");
  const novaToken = await deployTokenToNova(novaDeployer, novaProxyAdmin, l1Token);

  // step 1
  console.log("Init L2 governance");
  const l2DeployResult = await initL2Governance(arbDeployer, l2GovernanceFactory, l1Token.address);

  // step 2
  console.log("Init L1 governance");
  const l1DeployResult = await initL1Governance(
    l1GovernanceFactory,
    l1UpgradeExecutorLogic,
    l2DeployResult
  );

  // step 3
  console.log("Set executor roles");
  await setExecutorRoles(
    l1DeployResult,
    l2GovernanceFactory,
    novaUpgradeExecutorProxy,
    novaProxyAdmin,
    novaDeployer
  );

  console.log("Post deployment L1 token tasks");
  await postDeploymentL1TokenTasks(
    l1Token,
    l2DeployResult.token,
    novaToken.address,
    l1ReverseGateway,
    ethDeployer,
    arbDeployer,
    novaDeployer
  );

  console.log("Post deployment L2 token tasks");
  await postDeploymentL2TokenTasks(arbDeployer, l2DeployResult);

  // deploy ARB distributor
  console.log("Deploy TokenDistributor");
  await deployAndInitTokenDistributor(arbDeployer, l2DeployResult, arbDeployer);
};

async function deployL1LogicContracts(ethDeployer: Signer) {
  const l1UpgradeExecutorLogic = await new UpgradeExecutor__factory(ethDeployer).deploy();

  // store address
  deployedContracts["l1UpgradeExecutorLogic"] = l1UpgradeExecutorLogic.address;

  return l1UpgradeExecutorLogic;
}

async function deployL2LogicContracts(arbDeployer: Signer) {
  const timelockLogic = await new ArbitrumTimelock__factory(arbDeployer).deploy();
  const governorLogic = await new L2ArbitrumGovernor__factory(arbDeployer).deploy();
  const fixedDelegateLogic = await new FixedDelegateErc20Wallet__factory(arbDeployer).deploy();
  const l2TokenLogic = await new L2ArbitrumToken__factory(arbDeployer).deploy();
  const upgradeExecutor = await new UpgradeExecutor__factory(arbDeployer).deploy();

  // store addresses
  deployedContracts["l2TimelockLogic"] = timelockLogic.address;
  deployedContracts["l2GovernorLogic"] = governorLogic.address;
  deployedContracts["l2FixedDelegateLogic"] = fixedDelegateLogic.address;
  deployedContracts["l2TokenLogic"] = l2TokenLogic.address;
  deployedContracts["l2UpgradeExecutorLogic"] = upgradeExecutor.address;

  return { timelockLogic, governorLogic, fixedDelegateLogic, l2TokenLogic, upgradeExecutor };
}

async function deployL1GovernanceFactory(ethDeployer: Signer) {
  const l1GovernanceFactory = await new L1GovernanceFactory__factory(ethDeployer).deploy();
  await l1GovernanceFactory.deployed();

  // store address
  deployedContracts["l1GovernanceFactory"] = l1GovernanceFactory.address;

  return l1GovernanceFactory;
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
  await l2GovernanceFactory.deployed();

  // store address
  deployedContracts["l2GovernanceFactory"] = l2GovernanceFactory.address;

  return l2GovernanceFactory;
}

async function deployReverseGateways(
  l1GovernanceFactory: L1GovernanceFactory,
  l2GovernanceFactory: L2GovernanceFactory,
  ethDeployer: Signer,
  arbDeployer: Signer
): Promise<L1ForceOnlyReverseCustomGateway> {
  //// deploy reverse gateway on L1

  // deploy logic
  const l1ReverseCustomGatewayLogic = await new L1ForceOnlyReverseCustomGateway__factory(
    ethDeployer
  ).deploy();
  await l1ReverseCustomGatewayLogic.deployed();

  // deploy proxy
  const l1ProxyAdmin = await l1GovernanceFactory.proxyAdminAddress();
  const l1ReverseCustomGatewayProxy = await new TransparentUpgradeableProxy__factory(
    ethDeployer
  ).deploy(l1ReverseCustomGatewayLogic.address, l1ProxyAdmin, "0x");
  await l1ReverseCustomGatewayProxy.deployed();

  // store addresses
  deployedContracts["l1ReverseCustomGatewayLogic"] = l1ReverseCustomGatewayLogic.address;
  deployedContracts["l1ReverseCustomGatewayProxy"] = l1ReverseCustomGatewayProxy.address;

  //// deploy reverse gateway on L2

  // deploy logic
  const l2ReverseCustomGatewayLogic = await new L2ReverseCustomGateway__factory(
    arbDeployer
  ).deploy();
  await l2ReverseCustomGatewayLogic.deployed();

  // deploy proxy
  const l2ProxyAdmin = await l2GovernanceFactory.proxyAdminLogic();
  const l2ReverseCustomGatewayProxy = await new TransparentUpgradeableProxy__factory(
    arbDeployer
  ).deploy(l2ReverseCustomGatewayLogic.address, l2ProxyAdmin, "0x", {});
  await l2ReverseCustomGatewayProxy.deployed();

  //store addresses
  deployedContracts["l2ReverseCustomGatewayLogic"] = l2ReverseCustomGatewayLogic.address;
  deployedContracts["l2ReverseCustomGatewayProxy"] = l2ReverseCustomGatewayProxy.address;

  //// init gateways

  // init L1 reverse gateway
  const l1ReverseCustomGateway = L1ForceOnlyReverseCustomGateway__factory.connect(
    l1ReverseCustomGatewayProxy.address,
    ethDeployer
  );
  await (
    await l1ReverseCustomGateway.initialize(
      l2ReverseCustomGatewayProxy.address,
      GovernanceConstants.L1_ARB_ROUTER,
      GovernanceConstants.L1_ARB_INBOX,
      await ethDeployer.getAddress()
    )
  ).wait();

  // init L2 reverse gateway
  const l2ReverseCustomGateway = L2ReverseCustomGateway__factory.connect(
    l2ReverseCustomGatewayProxy.address,
    arbDeployer
  );
  await (
    await l2ReverseCustomGateway.initialize(
      l1ReverseCustomGateway.address,
      GovernanceConstants.L2_GATEWAY_ROUTER
    )
  ).wait();

  return l1ReverseCustomGateway;
}

async function deployAndInitL1Token(
  l1GovernanceFactory: L1GovernanceFactory,
  l1ReverseCustomGateway: L1ForceOnlyReverseCustomGateway,
  ethDeployer: Signer
) {
  // deploy logic
  const l1TokenLogic = await new L1ArbitrumToken__factory(ethDeployer).deploy();
  await l1TokenLogic.deployed();

  // deploy proxy
  const l1ProxyAdmin = await l1GovernanceFactory.proxyAdminAddress();
  const l1TokenProxy = await new TransparentUpgradeableProxy__factory(ethDeployer).deploy(
    l1TokenLogic.address,
    l1ProxyAdmin,
    "0x"
  );
  await l1TokenProxy.deployed();

  // store addresses
  deployedContracts["l1TokenLogic"] = l1TokenLogic.address;
  deployedContracts["l1TokenProxy"] = l1TokenProxy.address;

  // init L1 token
  const l1Token = L1ArbitrumToken__factory.connect(l1TokenProxy.address, ethDeployer);
  await (
    await l1Token.initialize(
      l1ReverseCustomGateway.address,
      GovernanceConstants.L1_NOVA_ROUTER,
      GovernanceConstants.L1_NOVA_GATEWAY
    )
  ).wait();

  return { l1Token };
}

async function deployNovaUpgradeExecutor(novaDeployer: Signer) {
  // deploy proxy admin
  const novaProxyAdmin = await new ProxyAdmin__factory(novaDeployer).deploy();
  await novaProxyAdmin.deployed();

  // deploy logic
  const novaUpgradeExecutorLogic = await new UpgradeExecutor__factory(novaDeployer).deploy();

  // deploy proxy with proxyAdmin as owner
  const novaUpgradeExecutorProxy = await new TransparentUpgradeableProxy__factory(
    novaDeployer
  ).deploy(novaUpgradeExecutorLogic.address, novaProxyAdmin.address, "0x");
  await novaUpgradeExecutorProxy.deployed();

  // store addresses
  deployedContracts["novaProxyAdmin"] = novaProxyAdmin.address;
  deployedContracts["novaUpgradeExecutorLogic"] = novaUpgradeExecutorLogic.address;
  deployedContracts["novaUpgradeExecutorProxy"] = novaUpgradeExecutorProxy.address;

  return { novaProxyAdmin, novaUpgradeExecutorProxy };
}

async function deployTokenToNova(
  novaDeployer: Signer,
  proxyAdmin: ProxyAdmin,
  l1Token: L1ArbitrumToken
) {
  // deploy token logic
  const novaTokenLogic = await new L2CustomGatewayToken__factory(novaDeployer).deploy();

  // deploy token proxy
  const novaTokenProxy = await new TransparentUpgradeableProxy__factory(novaDeployer).deploy(
    novaTokenLogic.address,
    proxyAdmin.address,
    "0x"
  );
  await novaTokenProxy.deployed();

  // init
  const novaToken = L2CustomGatewayToken__factory.connect(novaTokenProxy.address, novaDeployer);
  await (
    await novaToken.initialize(
      GovernanceConstants.NOVA_TOKEN_NAME,
      GovernanceConstants.NOVA_TOKEN_SYMBOL,
      GovernanceConstants.NOVA_TOKEN_DECIMALS,
      GovernanceConstants.NOVA_TOKEN_GATEWAY,
      l1Token.address
    )
  ).wait();

  // store addresses
  deployedContracts["novaTokenLogic"] = novaTokenLogic.address;
  deployedContracts["novaTokenProxy"] = novaTokenProxy.address;

  return novaToken;
}

async function initL2Governance(
  arbDeployer: Signer,
  l2GovernanceFactory: L2GovernanceFactory,
  l1TokenAddress: string
) {
  const arbInitialSupplyRecipientAddr = await arbDeployer.getAddress();

  // deploy
  const l2GovDeployReceipt = await (
    await l2GovernanceFactory.deployStep1({
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
      _l2EmergencySecurityCouncil: GovernanceConstants.L2_9_OF_12_SECURITY_COUNCIL,
    })
  ).wait();

  // get deployed contract addresses
  const l2DeployResult = l2GovDeployReceipt.events?.filter(
    (e) => e.topics[0] === l2GovernanceFactory.interface.getEventTopic("Deployed")
  )[0].args as unknown as L2DeployedEventObject;

  // store addresses
  deployedContracts["l2CoreGoverner"] = l2DeployResult.coreGoverner;
  deployedContracts["l2CoreTimelock"] = l2DeployResult.coreTimelock;
  deployedContracts["l2Executor"] = l2DeployResult.executor;
  deployedContracts["l2ProxyAdmin"] = l2DeployResult.proxyAdmin;
  deployedContracts["l2Token"] = l2DeployResult.token;
  deployedContracts["l2TreasuryGoverner"] = l2DeployResult.treasuryGoverner;
  deployedContracts["l2ArbTreasury"] = l2DeployResult.arbTreasury;

  return l2DeployResult;
}

async function initL1Governance(
  l1GovernanceFactory: L1GovernanceFactory,
  l1UpgradeExecutorLogic: UpgradeExecutor,
  l2DeployResult: L2DeployedEventObject
) {
  // deploy
  const l1GovDeployReceipt = await (
    await l1GovernanceFactory.deployStep2(
      l1UpgradeExecutorLogic.address,
      GovernanceConstants.L1_TIMELOCK_DELAY,
      GovernanceConstants.L1_ARB_INBOX,
      l2DeployResult.coreTimelock,
      GovernanceConstants.L1_9_OF_12_SECURITY_COUNCIL
    )
  ).wait();

  // get deployed contract addresses
  const l1DeployResult = l1GovDeployReceipt.events?.filter(
    (e) => e.topics[0] === l1GovernanceFactory.interface.getEventTopic("Deployed")
  )[0].args as unknown as L1DeployedEventObject;

  // store contract addresses
  deployedContracts["l1Executor"] = l1DeployResult.executor;
  deployedContracts["l1ProxyAdmin"] = l1DeployResult.proxyAdmin;
  deployedContracts["l1Timelock"] = l1DeployResult.timelock;

  return l1DeployResult;
}

async function setExecutorRoles(
  l1DeployResult: L1DeployedEventObject,
  l2GovernanceFactory: L2GovernanceFactory,
  novaUpgradeExecutorProxy: TransparentUpgradeableProxy,
  novaProxyAdmin: ProxyAdmin,
  novaDeployer: Signer
) {
  const l1TimelockAddress = new Address(l1DeployResult.timelock);
  const l1TimelockAliased = l1TimelockAddress.applyAlias().value;

  // set executors on L2
  await l2GovernanceFactory.deployStep3(l1TimelockAliased);

  // set executors on Nova
  const novaUpgradeExecutor = UpgradeExecutor__factory.connect(
    novaUpgradeExecutorProxy.address,
    novaDeployer
  );
  await novaUpgradeExecutor.initialize(novaUpgradeExecutor.address, [
    l1TimelockAliased,
    GovernanceConstants.NOVA_9_OF_12_SECURITY_COUNCIL,
  ]);

  // transfer ownership over novaProxyAdmin to executor
  await novaProxyAdmin.transferOwnership(novaUpgradeExecutor.address);
}

async function postDeploymentL1TokenTasks(
  l1Token: L1ArbitrumToken,
  arbTokenAddress: string,
  novaTokenAddress: string,
  l1ReverseCustomGateway: L1ForceOnlyReverseCustomGateway,
  ethDeployer: Signer,
  arbDeployer: Signer,
  novaDeployer: Signer
) {
  //// register token on ArbOne Gateway

  // 1 million gas limit
  const arbMaxGas = BigNumber.from(1000000);
  const arbGasPrice = (await arbDeployer.provider!.getGasPrice()).mul(2);

  const arbInbox = Inbox__factory.connect(await l1ReverseCustomGateway.inbox(), ethDeployer);
  const arbGatewayRegistrationData = L2CustomGateway__factory.createInterface().encodeFunctionData(
    "registerTokenFromL1",
    [[l1Token.address], [arbTokenAddress]]
  );

  const arbGatewaySubmissionFee = (
    await arbInbox.callStatic.calculateRetryableSubmissionFee(
      ethers.utils.hexDataLength(arbGatewayRegistrationData),
      0
    )
  ).mul(2);
  const valueForArbGateway = arbGatewaySubmissionFee.add(arbMaxGas.mul(arbGasPrice));

  const extraValue = 1000;
  const l1ArbRegistrationTx = await l1ReverseCustomGateway.forceRegisterTokenToL2(
    [l1Token.address],
    [arbTokenAddress],
    arbMaxGas,
    arbGasPrice,
    arbGatewaySubmissionFee,
    { value: valueForArbGateway.add(extraValue) }
  );

  //// wait for ArbOne gateway TXs
  const l1ArbRegistrationTxReceipt = await L1TransactionReceipt.monkeyPatchWait(
    l1ArbRegistrationTx
  ).wait();
  let l1ToArbMsgs = await l1ArbRegistrationTxReceipt.getL1ToL2Messages(arbDeployer.provider!);

  // status should be REDEEMED
  const arbSetTokenTx = await l1ToArbMsgs[0].waitForStatus();
  if (arbSetTokenTx.status != L1ToL2MessageStatus.REDEEMED) {
    throw new Error(
      "Register token L1 to L2 message not redeemed. Status: " + arbSetTokenTx.status.toString()
    );
  }

  //// register reverse gateway on ArbOne Router

  const l1GatewayRouter = L1GatewayRouter__factory.connect(
    await l1ReverseCustomGateway.router(),
    ethDeployer
  );

  const arbRouterRegistrationData = L2GatewayRouter__factory.createInterface().encodeFunctionData(
    "setGateway",
    [[l1Token.address], [l1ReverseCustomGateway.address]]
  );

  const arbRouterSubmissionFee = (
    await arbInbox.callStatic.calculateRetryableSubmissionFee(
      ethers.utils.hexDataLength(arbRouterRegistrationData),
      0
    )
  ).mul(2);
  const valueForArbRouter = arbRouterSubmissionFee.add(arbMaxGas.mul(arbGasPrice));

  const l1ArbRouterTx = await l1GatewayRouter.setGateways(
    [l1Token.address],
    [l1ReverseCustomGateway.address],
    arbMaxGas,
    arbGasPrice,
    arbRouterSubmissionFee,
    { value: valueForArbRouter.add(extraValue) }
  );

  //// wait for ArbOne router TXs

  const l1ArbRouterTxReceipt = await L1TransactionReceipt.monkeyPatchWait(l1ArbRouterTx).wait();
  l1ToArbMsgs = await l1ArbRouterTxReceipt.getL1ToL2Messages(arbDeployer.provider!);

  // status should be REDEEMED
  const arbSetGwTx = await l1ToArbMsgs[0].waitForStatus();
  if (arbSetGwTx.status != L1ToL2MessageStatus.REDEEMED) {
    throw new Error(
      "Register gateway L1 to L2 message not redeemed. Status: " + arbSetGwTx.status.toString()
    );
  }

  //// register token on Nova

  // 1 million gas limit
  const maxGas = BigNumber.from(1000000);
  const novaGasPrice = (await novaDeployer.provider!.getGasPrice()).mul(2);

  const novaGateway = L1CustomGateway__factory.connect(await l1Token.novaGateway(), ethDeployer);
  const novaInbox = Inbox__factory.connect(await novaGateway.inbox(), ethDeployer);

  // calcs for novaGateway
  const novaGatewayRegistrationData = L2CustomGateway__factory.createInterface().encodeFunctionData(
    "registerTokenFromL1",
    [[l1Token.address], [novaTokenAddress]]
  );
  const novaGatewaySubmissionFee = (
    await novaInbox.callStatic.calculateRetryableSubmissionFee(
      ethers.utils.hexDataLength(novaGatewayRegistrationData),
      0
    )
  ).mul(2);
  const valueForNovaGateway = novaGatewaySubmissionFee.add(maxGas.mul(novaGasPrice));

  // calcs for novaRouter
  const novaRouterRegistrationData = L2GatewayRouter__factory.createInterface().encodeFunctionData(
    "setGateway",
    [[l1Token.address], [novaGateway.address]]
  );
  const novaRouterSubmissionFee = (
    await novaInbox.callStatic.calculateRetryableSubmissionFee(
      ethers.utils.hexDataLength(novaRouterRegistrationData),
      0
    )
  ).mul(2);
  const valueForNovaRouter = novaRouterSubmissionFee.add(maxGas.mul(novaGasPrice));

  // do the registration
  const l1NovaRegistrationTx = await l1Token.registerTokenOnL2(
    {
      l2TokenAddress: novaTokenAddress,
      maxSubmissionCostForCustomGateway: novaGatewaySubmissionFee,
      maxSubmissionCostForRouter: novaRouterSubmissionFee,
      maxGasForCustomGateway: maxGas,
      maxGasForRouter: maxGas,
      gasPriceBid: novaGasPrice,
      valueForGateway: valueForNovaGateway,
      valueForRouter: valueForNovaRouter,
      creditBackAddress: await ethDeployer.getAddress(),
    },
    {
      value: valueForNovaGateway.add(valueForNovaRouter).add(extraValue),
    }
  );

  //// wait for L2 TXs

  const l1NovaRegistrationTxReceipt = await L1TransactionReceipt.monkeyPatchWait(
    l1NovaRegistrationTx
  ).wait();
  const l1ToNovaMsgs = await l1NovaRegistrationTxReceipt.getL1ToL2Messages(novaDeployer.provider!);

  // status should be REDEEMED
  const novaSetTokenTx = await l1ToNovaMsgs[0].waitForStatus();
  const novaSetGatewaysTX = await l1ToNovaMsgs[1].waitForStatus();
  if (novaSetTokenTx.status != L1ToL2MessageStatus.REDEEMED) {
    throw new Error(
      "Register token L1 to L2 message not redeemed. Status: " + novaSetTokenTx.status.toString()
    );
  }
  if (novaSetGatewaysTX.status != L1ToL2MessageStatus.REDEEMED) {
    throw new Error(
      "Set gateway L1 to L2 message not redeemed. Status: " + novaSetGatewaysTX.status.toString()
    );
  }
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

  // transfer tokens from arbDeployer to the treasury
  await l2Token
    .connect(arbInitialSupplyRecipient)
    .transfer(
      l2DeployResult.arbTreasury,
      parseEther(GovernanceConstants.L2_NUM_OF_TOKENS_FOR_TREASURY)
    );

  /// when distributor is deployed remaining tokens are transfered to it
}

async function deployAndInitTokenDistributor(
  arbDeployer: Signer,
  l2DeployResult: L2DeployedEventObject,
  arbInitialSupplyRecipient: Signer
) {
  // deploy TokenDistributor
  const delegationExcludeAddress = await L2ArbitrumGovernor__factory.connect(
    l2DeployResult.coreGoverner,
    arbDeployer
  ).EXCLUDE_ADDRESS();
  const tokenDistributor = await new TokenDistributor__factory(arbDeployer).deploy(
    l2DeployResult.token,
    GovernanceConstants.L2_SWEEP_RECECIVER,
    await arbDeployer.getAddress(),
    GovernanceConstants.L2_CLAIM_PERIOD_START,
    GovernanceConstants.L2_CLAIM_PERIOD_END,
    delegationExcludeAddress
  );
  await tokenDistributor.deployed();

  // store address
  deployedContracts["l2TokenDistributor"] = tokenDistributor.address;

  // transfer tokens from arbDeployer to the distributor
  const l2Token = L2ArbitrumToken__factory.connect(
    l2DeployResult.token,
    arbInitialSupplyRecipient.provider!
  );
  await (
    await l2Token
      .connect(arbInitialSupplyRecipient)
      .transfer(
        tokenDistributor.address,
        parseEther(GovernanceConstants.L2_NUM_OF_TOKENS_FOR_CLAIMING)
      )
  ).wait();

  // set claim recipients
  await setClaimRecipients(tokenDistributor, arbDeployer);

  // check num of recipients and claimable amount before transferring ownership
  const numOfRecipientsSet = await getNumberOfRecipientsSet(tokenDistributor);
  if (numOfRecipientsSet != GovernanceConstants.L2_NUM_OF_RECIPIENTS) {
    throw new Error("Incorrect number of recipients set: " + numOfRecipientsSet);
  }
  const totalClaimable = await tokenDistributor.totalClaimable();
  if (!totalClaimable.eq(parseEther(GovernanceConstants.L2_NUM_OF_TOKENS_FOR_CLAIMING))) {
    throw new Error("Incorrect totalClaimable amount of tokenDistributor: " + totalClaimable);
  }

  // transfer ownership to L2 UpgradeExecutor
  await (await tokenDistributor.transferOwnership(l2DeployResult.executor)).wait();
}

/**
 * Write addresses of deployed contracts to local JSON file
 */
function writeAddresses() {
  const fs = require("fs");
  fs.writeFileSync(DEPLOYED_CONTRACTS_FILE_NAME, JSON.stringify(deployedContracts));
}

async function main() {
  console.log("Start governance deployment process...");
  try {
    await deployGovernance();
  } finally {
    // write addresses of deployed contracts even when exception is thrown
    console.log("Write deployed contract addresses to deployedContracts.json");
    writeAddresses();
  }
  console.log("Deployment finished!");
}

main()
  .then(() => console.log("Done."))
  .catch(console.error);
