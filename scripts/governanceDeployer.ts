import { Address, L1ToL2MessageStatus, L1TransactionReceipt, L2Network } from "@arbitrum/sdk";
import { Inbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Inbox__factory";
import { L1CustomGateway__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L1CustomGateway__factory";
import { L1GatewayRouter__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L1GatewayRouter__factory";
import { L2CustomGateway__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L2CustomGateway__factory";
import { L2GatewayRouter__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L2GatewayRouter__factory";
import { BigNumber, Contract, ethers, Signer } from "ethers";
import { Interface, parseEther } from "ethers/lib/utils";
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
  TokenDistributor,
  TokenDistributor__factory,
  TransparentUpgradeableProxy,
  TransparentUpgradeableProxy__factory,
  UpgradeExecutor,
  UpgradeExecutor__factory,
} from "../typechain-types";
import {
  L1ForceOnlyReverseCustomGateway,
  L1ForceOnlyReverseCustomGateway__factory,
  L2CustomGatewayToken,
  L2CustomGatewayToken__factory,
  L2ReverseCustomGateway__factory,
} from "../token-bridge-contracts/build/types";
import {
  DeployedEventObject as L1DeployedEventObject,
  L1GovernanceFactory,
} from "../typechain-types/src/L1GovernanceFactory";
import {
  DeployedEventObject as L2DeployedEventObject,
  L2GovernanceFactory,
} from "../typechain-types/src/L2GovernanceFactory";
import { getDeployersAndConfig as getDeployersAndConfig, isDeployingToNova } from "./providerSetup";
import { setClaimRecipients } from "./tokenDistributorHelper";
import { deployVestedWallets, loadVestedRecipients } from "./vestedWalletsDeployer";
import fs from "fs";
import path from "path";
import { Provider } from "@ethersproject/providers";

// store address for every deployed contract
interface DeployProgressCache {
  l1UpgradeExecutorLogic?: string;
  l2TimelockLogic?: string;
  l2GovernorLogic?: string;
  l2FixedDelegateLogic?: string;
  l2TokenLogic?: string;
  l2UpgradeExecutorLogic?: string;
  l1GovernanceFactory?: string;
  l2GovernanceFactory?: string;
  l1ReverseCustomGatewayLogic?: string;
  l1ReverseCustomGatewayProxy?: string;
  l2ReverseCustomGatewayLogic?: string;
  l2ReverseCustomGatewayProxy?: string;
  l1TokenLogic?: string;
  l1TokenProxy?: string;
  novaProxyAdmin?: string;
  novaUpgradeExecutorLogic?: string;
  novaUpgradeExecutorProxy?: string;
  novaTokenLogic?: string;
  novaTokenProxy?: string;
  l2CoreGoverner?: string;
  l2CoreTimelock?: string;
  l2Executor?: string;
  l2ProxyAdmin?: string;
  l2Token?: string;
  l2TreasuryGoverner?: string;
  l2ArbTreasury?: string;
  arbitrumDAOConstitution?: string;
  l1Executor?: string;
  l1ProxyAdmin?: string;
  l1Timelock?: string;
  step3Executed?: boolean;
  executorRolesSetOnNova1?: boolean;
  executorRolesSetOnNova2?: boolean;
  registerTokenArbOne1?: boolean;
  registerTokenArbOne2?: boolean;
  registerTokenNova?: boolean;
  l2TokenTask1?: boolean;
  l2TokenTask2?: boolean;
  vestedWalletInProgress?: boolean;
  vestedWalletFactory?: string;
  l2TokenDistributor?: string;
  l2TokenTransferFunds?: boolean;
  l2TokenTransferOwnership?: boolean;
  distributorSetRecipientsStartBlock?: number;
  distributorSetRecipientsEndBlock?: number;
}
let deployedContracts: DeployProgressCache = {};
const DEPLOYED_CONTRACTS_FILE_NAME = "deployedContracts.json";
const VESTED_RECIPIENTS_FILE_NAME = "files/vestedRecipients.json";

export type TypeChainContractFactory<TContract extends Contract> = {
  deploy(...args: Array<any>): Promise<TContract>;
};

export type TypeChainContractFactoryStatic<TContract extends Contract> = {
  connect(address: string, signerOrProvider: Provider | Signer): TContract;
  createInterface(): Interface;
  new (signer: Signer): TypeChainContractFactory<TContract>;
};

type StringProps<T> = {
  [k in keyof T as T[k] extends string | undefined ? k : never]: T[k];
};
async function getOrInit<TContract extends Contract>(
  cacheKey: keyof StringProps<DeployProgressCache>,
  deployer: Signer,
  contractFactory: TypeChainContractFactoryStatic<TContract>,
  deploy: () => Promise<TContract>
): Promise<TContract> {
  const address = deployedContracts[cacheKey];
  if (!address) {
    const contract = await deploy();
    await contract.deployed();
    deployedContracts[cacheKey] = contract.address;
    return contract;
  } else {
    return contractFactory.connect(address, deployer);
  }
}

async function getOrInitDefault<TContract extends Contract>(
  cacheKey: keyof StringProps<DeployProgressCache>,
  deployer: Signer,
  contractFactory: TypeChainContractFactoryStatic<TContract>
) {
  return await getOrInit(cacheKey, deployer, contractFactory, () =>
    new contractFactory(deployer).deploy()
  );
}

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
  const { ethDeployer, arbDeployer, novaDeployer, deployerConfig, arbNetwork, novaNetwork } =
    await getDeployersAndConfig();

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
    arbDeployer,
    arbNetwork
  );

  console.log("Deploy and init L1 Arbitrum token");
  const { l1Token } = await deployAndInitL1Token(
    l1GovernanceFactory,
    l1ReverseGateway,
    ethDeployer,
    novaNetwork
  );

  let _novaProxyAdmin: ProxyAdmin | undefined;
  let _novaUpgradeExecutorProxy: TransparentUpgradeableProxy | undefined;
  let _novaToken: L2CustomGatewayToken | undefined;
  if (isDeployingToNova()) {
    console.log("Deploy UpgradeExecutor to Nova");
    const { novaProxyAdmin, novaUpgradeExecutorProxy } = await deployNovaUpgradeExecutor(
      novaDeployer
    );
    _novaProxyAdmin = novaProxyAdmin;
    _novaUpgradeExecutorProxy = novaUpgradeExecutorProxy;

    console.log("Deploy token to Nova");
    const novaToken = await deployTokenToNova(
      novaDeployer,
      novaProxyAdmin,
      l1Token,
      novaNetwork,
      deployerConfig
    );
    _novaToken = novaToken;
  }

  // step 1
  console.log("Init L2 governance");
  const l2DeployResult = await initL2Governance(
    arbDeployer,
    l2GovernanceFactory,
    l1Token.address,
    deployerConfig
  );

  // step 2
  console.log("Init L1 governance");
  const l1DeployResult = await initL1Governance(
    l1GovernanceFactory,
    l1UpgradeExecutorLogic,
    l2DeployResult,
    arbNetwork,
    deployerConfig
  );

  // step 3
  console.log("Set executor roles");
  await setExecutorRoles(l1DeployResult, l2GovernanceFactory);

  if (isDeployingToNova()) {
    console.log("Set executor roles on Nova");
    await setExecutorRolesOnNova(
      l1DeployResult,
      _novaUpgradeExecutorProxy!,
      _novaProxyAdmin!,
      novaDeployer,
      deployerConfig
    );
  }

  console.log("Register token on ArbOne");
  await registerTokenOnArbOne(
    l1Token,
    l2DeployResult.token,
    l1ReverseGateway,
    ethDeployer,
    arbDeployer
  );

  if (isDeployingToNova()) {
    console.log("Register token on Nova");
    await registerTokenOnNova(l1Token, _novaToken!.address, ethDeployer, novaDeployer);
  }

  console.log("Post deployment L2 token tasks");
  await postDeploymentL2TokenTasks(arbDeployer, l2DeployResult, deployerConfig);

  console.log("Distribute to vested wallets");
  await deployAndTransferVestedWallets(
    arbDeployer,
    arbDeployer,
    l2DeployResult.token,
    deployerConfig
  );

  // deploy ARB distributor
  console.log("Deploy TokenDistributor");
  const tokenDistributor = await deployTokenDistributor(
    arbDeployer,
    l2DeployResult,
    arbDeployer,
    deployerConfig
  );

  // write addresses before the last step which takes hours
  console.log("Write deployed contract addresses to deployedContracts.json");
  writeAddresses();

  console.log("Set TokenDistributor recipients");
  await initTokenDistributor(
    tokenDistributor,
    arbDeployer,
    l2DeployResult.executor,
    deployerConfig
  );
};

async function deployL1LogicContracts(ethDeployer: Signer) {
  return await getOrInitDefault("l1UpgradeExecutorLogic", ethDeployer, UpgradeExecutor__factory);
}

async function deployL2LogicContracts(arbDeployer: Signer) {
  return {
    timelockLogic: await getOrInitDefault(
      "l2TimelockLogic",
      arbDeployer,
      ArbitrumTimelock__factory
    ),
    governorLogic: await getOrInitDefault(
      "l2GovernorLogic",
      arbDeployer,
      L2ArbitrumGovernor__factory
    ),
    fixedDelegateLogic: await getOrInitDefault(
      "l2FixedDelegateLogic",
      arbDeployer,
      FixedDelegateErc20Wallet__factory
    ),
    l2TokenLogic: await getOrInitDefault("l2TokenLogic", arbDeployer, L2ArbitrumToken__factory),
    upgradeExecutor: await getOrInitDefault(
      "l2UpgradeExecutorLogic",
      arbDeployer,
      UpgradeExecutor__factory
    ),
  };
}

async function deployL1GovernanceFactory(ethDeployer: Signer) {
  return await getOrInitDefault("l1GovernanceFactory", ethDeployer, L1GovernanceFactory__factory);
}

async function deployL2GovernanceFactory(
  arbDeployer: Signer,
  timelockLogic: ArbitrumTimelock,
  governorLogic: L2ArbitrumGovernor,
  fixedDelegateLogic: FixedDelegateErc20Wallet,
  l2TokenLogic: L2ArbitrumToken,
  upgradeExecutor: UpgradeExecutor
) {
  return await getOrInit("l2GovernanceFactory", arbDeployer, L2GovernanceFactory__factory, () =>
    new L2GovernanceFactory__factory(arbDeployer).deploy(
      timelockLogic.address,
      governorLogic.address,
      timelockLogic.address,
      fixedDelegateLogic.address,
      governorLogic.address,
      l2TokenLogic.address,
      upgradeExecutor.address
    )
  );
}

async function deployReverseGateways(
  l1GovernanceFactory: L1GovernanceFactory,
  l2GovernanceFactory: L2GovernanceFactory,
  ethDeployer: Signer,
  arbDeployer: Signer,
  arbNetwork: L2Network
): Promise<L1ForceOnlyReverseCustomGateway> {
  if (deployedContracts.l1ReverseCustomGatewayProxy) {
    return L1ForceOnlyReverseCustomGateway__factory.connect(
      deployedContracts.l1ReverseCustomGatewayProxy,
      ethDeployer
    );
  } else {
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

    //// init gateways

    // init L1 reverse gateway
    const l1ReverseCustomGateway = L1ForceOnlyReverseCustomGateway__factory.connect(
      l1ReverseCustomGatewayProxy.address,
      ethDeployer
    );
    await (
      await l1ReverseCustomGateway.initialize(
        l2ReverseCustomGatewayProxy.address,
        arbNetwork.tokenBridge.l1GatewayRouter,
        arbNetwork.ethBridge.inbox,
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
        arbNetwork.tokenBridge.l2GatewayRouter
      )
    ).wait();

    // store addresses
    deployedContracts.l1ReverseCustomGatewayLogic = l1ReverseCustomGatewayLogic.address;
    deployedContracts.l1ReverseCustomGatewayProxy = l1ReverseCustomGatewayProxy.address;
    deployedContracts.l2ReverseCustomGatewayLogic = l2ReverseCustomGatewayLogic.address;
    deployedContracts.l2ReverseCustomGatewayProxy = l2ReverseCustomGatewayProxy.address;

    return l1ReverseCustomGateway;
  }
}

async function deployAndInitL1Token(
  l1GovernanceFactory: L1GovernanceFactory,
  l1ReverseCustomGateway: L1ForceOnlyReverseCustomGateway,
  ethDeployer: Signer,
  novaNetwork: L2Network
) {
  // deploy logic
  const l1TokenLogic = await getOrInitDefault(
    "l1TokenLogic",
    ethDeployer,
    L1ArbitrumToken__factory
  );

  // deploy proxy
  const l1Token = await getOrInit(
    "l1TokenProxy",
    ethDeployer,
    L1ArbitrumToken__factory,
    async () => {
      const proxy = await new TransparentUpgradeableProxy__factory(ethDeployer).deploy(
        l1TokenLogic.address,
        await l1GovernanceFactory.proxyAdminAddress(),
        "0x"
      );
      const token = L1ArbitrumToken__factory.connect(proxy.address, ethDeployer);
      await (
        await token.initialize(
          l1ReverseCustomGateway.address,
          novaNetwork.tokenBridge.l1GatewayRouter,
          novaNetwork.tokenBridge.l1CustomGateway,
          // for some intialize fails on a local network without this
          { gasLimit: 300000 }
        )
      ).wait();

      return token;
    }
  );

  return { l1Token };
}

async function deployNovaUpgradeExecutor(novaDeployer: Signer) {
  // deploy proxy admin
  const novaProxyAdmin = await getOrInitDefault(
    "novaProxyAdmin",
    novaDeployer,
    ProxyAdmin__factory
  );

  // deploy logic
  const novaUpgradeExecutorLogic = await getOrInitDefault(
    "novaUpgradeExecutorLogic",
    novaDeployer,
    UpgradeExecutor__factory
  );

  // deploy proxy with proxyAdmin as owner
  const novaUpgradeExecutorProxy = await getOrInit(
    "novaUpgradeExecutorProxy",
    novaDeployer,
    TransparentUpgradeableProxy__factory,
    () =>
      new TransparentUpgradeableProxy__factory(novaDeployer).deploy(
        novaUpgradeExecutorLogic.address,
        novaProxyAdmin.address,
        "0x"
      )
  );

  return { novaProxyAdmin, novaUpgradeExecutorProxy };
}

async function deployTokenToNova(
  novaDeployer: Signer,
  proxyAdmin: ProxyAdmin,
  l1Token: L1ArbitrumToken,
  novaNetwork: L2Network,
  config: {
    NOVA_TOKEN_NAME: string;
    NOVA_TOKEN_SYMBOL: string;
    NOVA_TOKEN_DECIMALS: number;
  }
) {
  // deploy token logic
  const novaTokenLogic = await getOrInitDefault(
    "novaTokenLogic",
    novaDeployer,
    L2CustomGatewayToken__factory
  );

  // deploy token proxy
  const novaTokenProxy = await getOrInit(
    "novaTokenProxy",
    novaDeployer,
    L2CustomGatewayToken__factory,
    async () => {
      const proxy = await new TransparentUpgradeableProxy__factory(novaDeployer).deploy(
        novaTokenLogic.address,
        proxyAdmin.address,
        "0x"
      );
      await proxy.deployed();
      const novaToken = L2CustomGatewayToken__factory.connect(proxy.address, novaDeployer);
      await (
        await novaToken.initialize(
          config.NOVA_TOKEN_NAME,
          config.NOVA_TOKEN_SYMBOL,
          config.NOVA_TOKEN_DECIMALS,
          novaNetwork.tokenBridge.l2CustomGateway,
          l1Token.address
        )
      ).wait();

      return novaToken;
    }
  );

  return novaTokenProxy;
}

async function initL2Governance(
  arbDeployer: Signer,
  l2GovernanceFactory: L2GovernanceFactory,
  l1TokenAddress: string,
  config: {
    L2_TIMELOCK_DELAY: number;
    L2_TOKEN_INITIAL_SUPPLY: string;
    L2_7_OF_12_SECURITY_COUNCIL: string;
    L2_CORE_QUORUM_TRESHOLD: number;
    L2_TREASURY_QUORUM_TRESHOLD: number;
    L2_PROPOSAL_TRESHOLD: number;
    L2_VOTING_DELAY: number;
    L2_VOTING_PERIOD: number;
    L2_MIN_PERIOD_AFTER_QUORUM: number;
    L2_9_OF_12_SECURITY_COUNCIL: string;
    ARBITRUM_DAO_CONSTITUTION_HASH: string;
    L2_TREASURY_TIMELOCK_DELAY: number
  }
) {
  if (!deployedContracts.l2CoreGoverner) {
    const arbInitialSupplyRecipientAddr = await arbDeployer.getAddress();

    // deploy
    const l2GovDeployReceipt = await (
      await l2GovernanceFactory.deployStep1({
        _l2MinTimelockDelay: config.L2_TIMELOCK_DELAY,
        _l2TokenInitialSupply: parseEther(config.L2_TOKEN_INITIAL_SUPPLY),
        _l2NonEmergencySecurityCouncil: config.L2_7_OF_12_SECURITY_COUNCIL,
        _coreQuorumThreshold: config.L2_CORE_QUORUM_TRESHOLD,
        _l1Token: l1TokenAddress,
        _treasuryQuorumThreshold: config.L2_TREASURY_QUORUM_TRESHOLD,
        _proposalThreshold: config.L2_PROPOSAL_TRESHOLD,
        _votingDelay: config.L2_VOTING_DELAY,
        _votingPeriod: config.L2_VOTING_PERIOD,
        _minPeriodAfterQuorum: config.L2_MIN_PERIOD_AFTER_QUORUM,
        _l2InitialSupplyRecipient: arbInitialSupplyRecipientAddr,
        _l2EmergencySecurityCouncil: config.L2_9_OF_12_SECURITY_COUNCIL,
        _constitutionHash: config.ARBITRUM_DAO_CONSTITUTION_HASH,
        _l2TreasuryMinTimelockDelay: config.L2_TREASURY_TIMELOCK_DELAY
      })
    ).wait();

    // get deployed contract addresses
    const l2DeployResult = l2GovDeployReceipt.events?.filter(
      (e) => e.topics[0] === l2GovernanceFactory.interface.getEventTopic("Deployed")
    )[0].args as unknown as L2DeployedEventObject;

    // store addresses
    deployedContracts.l2CoreGoverner = l2DeployResult.coreGoverner;
    deployedContracts.l2CoreTimelock = l2DeployResult.coreTimelock;
    deployedContracts.l2Executor = l2DeployResult.executor;
    deployedContracts.l2ProxyAdmin = l2DeployResult.proxyAdmin;
    deployedContracts.l2Token = l2DeployResult.token;
    deployedContracts.l2TreasuryGoverner = l2DeployResult.treasuryGoverner;
    deployedContracts.l2ArbTreasury = l2DeployResult.arbTreasury;
    deployedContracts.arbitrumDAOConstitution = l2DeployResult.arbitrumDAOConstitution;
  }
  return {
    token: deployedContracts.l2Token!,
    coreTimelock: deployedContracts.l2CoreTimelock!,
    coreGoverner: deployedContracts.l2CoreGoverner!,
    treasuryGoverner: deployedContracts.l2TreasuryGoverner!,
    arbTreasury: deployedContracts.l2ArbTreasury!,
    proxyAdmin: deployedContracts.l2ProxyAdmin!,
    executor: deployedContracts.l2Executor!,
    arbitrumDAOConstitution: deployedContracts.arbitrumDAOConstitution!,
  };
}

async function initL1Governance(
  l1GovernanceFactory: L1GovernanceFactory,
  l1UpgradeExecutorLogic: UpgradeExecutor,
  l2DeployResult: L2DeployedEventObject,
  arbNetwork: L2Network,
  config: {
    L1_TIMELOCK_DELAY: number;
    L1_9_OF_12_SECURITY_COUNCIL: string;
  }
) {
  if (!deployedContracts.l1Executor) {
    // deploy
    const l1GovDeployReceipt = await (
      await l1GovernanceFactory.deployStep2(
        l1UpgradeExecutorLogic.address,
        config.L1_TIMELOCK_DELAY,
        arbNetwork.ethBridge.inbox,
        l2DeployResult.coreTimelock,
        config.L1_9_OF_12_SECURITY_COUNCIL
      )
    ).wait();

    // get deployed contract addresses
    const l1DeployResult = l1GovDeployReceipt.events?.filter(
      (e) => e.topics[0] === l1GovernanceFactory.interface.getEventTopic("Deployed")
    )[0].args as unknown as L1DeployedEventObject;

    // store contract addresses
    deployedContracts.l1Executor = l1DeployResult.executor;
    deployedContracts.l1ProxyAdmin = l1DeployResult.proxyAdmin;
    deployedContracts.l1Timelock = l1DeployResult.timelock;
  }
  return {
    executor: deployedContracts.l1Executor!,
    proxyAdmin: deployedContracts.l1ProxyAdmin!,
    timelock: deployedContracts.l1Timelock!,
  };
}

async function setExecutorRoles(
  l1DeployResult: L1DeployedEventObject,
  l2GovernanceFactory: L2GovernanceFactory
) {
  if (!deployedContracts.step3Executed) {
    const l1TimelockAddress = new Address(l1DeployResult.timelock);
    const l1TimelockAliased = l1TimelockAddress.applyAlias().value;

    // set executors on L2
    await (await l2GovernanceFactory.deployStep3(l1TimelockAliased)).wait();

    deployedContracts.step3Executed = true;
  }
}

async function setExecutorRolesOnNova(
  l1DeployResult: L1DeployedEventObject,
  novaUpgradeExecutorProxy: TransparentUpgradeableProxy,
  novaProxyAdmin: ProxyAdmin,
  novaDeployer: Signer,
  config: {
    NOVA_9_OF_12_SECURITY_COUNCIL: string;
  }
) {
  if (!deployedContracts.executorRolesSetOnNova1) {
    const l1TimelockAddress = new Address(l1DeployResult.timelock);
    const l1TimelockAliased = l1TimelockAddress.applyAlias().value;

    // set executors on Nova
    const novaUpgradeExecutor = UpgradeExecutor__factory.connect(
      novaUpgradeExecutorProxy.address,
      novaDeployer
    );
    await (
      await novaUpgradeExecutor.initialize(novaUpgradeExecutor.address, [
        l1TimelockAliased,
        config.NOVA_9_OF_12_SECURITY_COUNCIL,
      ])
    ).wait();

    deployedContracts.executorRolesSetOnNova1 = true;
  }

  if (!deployedContracts.executorRolesSetOnNova2) {
    const novaUpgradeExecutor = UpgradeExecutor__factory.connect(
      novaUpgradeExecutorProxy.address,
      novaDeployer
    );
    // transfer ownership over novaProxyAdmin to executor
    await (await novaProxyAdmin.transferOwnership(novaUpgradeExecutor.address)).wait();

    deployedContracts.executorRolesSetOnNova2 = true;
  }
}

async function registerTokenOnArbOne(
  l1Token: L1ArbitrumToken,
  arbTokenAddress: string,
  l1ReverseCustomGateway: L1ForceOnlyReverseCustomGateway,
  ethDeployer: Signer,
  arbDeployer: Signer
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

  if (!deployedContracts.registerTokenArbOne1) {
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
    const l1ToArbMsgs = await l1ArbRegistrationTxReceipt.getL1ToL2Messages(arbDeployer.provider!);

    // status should be REDEEMED
    const arbSetTokenTx = await l1ToArbMsgs[0].waitForStatus();
    if (arbSetTokenTx.status != L1ToL2MessageStatus.REDEEMED) {
      throw new Error(
        "Register token L1 to L2 message not redeemed. Status: " + arbSetTokenTx.status.toString()
      );
    }

    deployedContracts.registerTokenArbOne1 = true;
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

  if (!deployedContracts.registerTokenArbOne2) {
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
    const l1ToArbMsgs = await l1ArbRouterTxReceipt.getL1ToL2Messages(arbDeployer.provider!);

    // status should be REDEEMED
    const arbSetGwTx = await l1ToArbMsgs[0].waitForStatus();
    if (arbSetGwTx.status != L1ToL2MessageStatus.REDEEMED) {
      throw new Error(
        "Register gateway L1 to L2 message not redeemed. Status: " + arbSetGwTx.status.toString()
      );
    }

    deployedContracts.registerTokenArbOne2 = true;
  }
}

async function registerTokenOnNova(
  l1Token: L1ArbitrumToken,
  novaTokenAddress: string,
  ethDeployer: Signer,
  novaDeployer: Signer
) {
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
  const extraValue = 1000;
  console.log("going in here");
  if (!deployedContracts.registerTokenNova) {
    console.log("in here a");

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
    console.log("in here b");

    const l1NovaRegistrationTxReceipt = await L1TransactionReceipt.monkeyPatchWait(
      l1NovaRegistrationTx
    ).wait();
    console.log("in here c");
    const l1ToNovaMsgs = await l1NovaRegistrationTxReceipt.getL1ToL2Messages(
      novaDeployer.provider!
    );
    console.log("in here d");

    // status should be REDEEMED
    const novaSetTokenTx = await l1ToNovaMsgs[0].waitForStatus();
    console.log("in here e");
    const novaSetGatewaysTX = await l1ToNovaMsgs[1].waitForStatus();
    console.log("in here f");
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

    deployedContracts.registerTokenNova = true;
  }
}

async function postDeploymentL2TokenTasks(
  arbInitialSupplyRecipient: Signer,
  l2DeployResult: L2DeployedEventObject,
  config: {
    L2_NUM_OF_TOKENS_FOR_TREASURY: string;
  }
) {
  if (!deployedContracts.l2TokenTask1) {
    // transfer L2 token ownership to upgradeExecutor
    const l2Token = L2ArbitrumToken__factory.connect(
      l2DeployResult.token,
      arbInitialSupplyRecipient.provider!
    );
    await (
      await l2Token.connect(arbInitialSupplyRecipient).transferOwnership(l2DeployResult.executor)
    ).wait();

    deployedContracts.l2TokenTask1 = true;
  }

  if (!deployedContracts.l2TokenTask2) {
    const l2Token = L2ArbitrumToken__factory.connect(
      l2DeployResult.token,
      arbInitialSupplyRecipient.provider!
    );
    // transfer tokens from arbDeployer to the treasury
    await (
      await l2Token
        .connect(arbInitialSupplyRecipient)
        .transfer(l2DeployResult.arbTreasury, parseEther(config.L2_NUM_OF_TOKENS_FOR_TREASURY))
    ).wait();

    deployedContracts.l2TokenTask2 = true;

    /// when distributor is deployed remaining tokens are transfered to it
  }
}

async function deployAndTransferVestedWallets(
  arbDeployer: Signer,
  arbInitialSupplyRecipient: Signer,
  l2TokenAddress: string,
  config: {
    L2_CLAIM_PERIOD_START: number;
  }
) {
  const tokenRecipientsByPoints = path.join(__dirname, "..", VESTED_RECIPIENTS_FILE_NAME);
  const recipients = loadVestedRecipients(tokenRecipientsByPoints);

  const oneYearInSeconds = 365 * 24 * 60 * 60;

  if (!deployedContracts.vestedWalletFactory) {
    // we dont currently have full error handling for errors thrown during
    // vested wallet deployment, for now just throw an error and require
    // manual intervention if an error occurs in here
    if (deployedContracts.vestedWalletInProgress) {
      throw new Error(
        "Vested wallet deployment started but a failure occurred, manual intervention required"
      );
    }
    deployedContracts.vestedWalletInProgress = true;

    const vestedWalletFactory = await deployVestedWallets(
      arbDeployer,
      arbInitialSupplyRecipient,
      l2TokenAddress,
      recipients,
      // start vesting in 1 years time
      config.L2_CLAIM_PERIOD_START + oneYearInSeconds,
      // vesting lasts for 3 years
      oneYearInSeconds * 3
    );
    deployedContracts.vestedWalletInProgress = undefined;
    deployedContracts.vestedWalletFactory = vestedWalletFactory.address;
  }
}

async function deployTokenDistributor(
  arbDeployer: Signer,
  l2DeployResult: L2DeployedEventObject,
  arbInitialSupplyRecipient: Signer,
  config: {
    L2_SWEEP_RECEIVER: string;
    L2_CLAIM_PERIOD_START: number;
    L2_CLAIM_PERIOD_END: number;
    L2_NUM_OF_TOKENS_FOR_CLAIMING: string;
    L2_NUM_OF_RECIPIENTS: number;
  }
): Promise<TokenDistributor> {
  // deploy TokenDistributor
  const delegationExcludeAddress = await L2ArbitrumGovernor__factory.connect(
    l2DeployResult.coreGoverner,
    arbDeployer
  ).EXCLUDE_ADDRESS();

  const tokenDistributor = await getOrInit(
    "l2TokenDistributor",
    arbDeployer,
    TokenDistributor__factory,
    async () => {
      return await new TokenDistributor__factory(arbDeployer).deploy(
        l2DeployResult.token,
        config.L2_SWEEP_RECEIVER,
        await arbDeployer.getAddress(),
        config.L2_CLAIM_PERIOD_START,
        config.L2_CLAIM_PERIOD_END,
        delegationExcludeAddress
      );
    }
  );

  if (!deployedContracts.l2TokenTransferFunds) {
    // transfer tokens from arbDeployer to the distributor
    const l2Token = L2ArbitrumToken__factory.connect(
      l2DeployResult.token,
      arbInitialSupplyRecipient.provider!
    );
    await (
      await l2Token
        .connect(arbInitialSupplyRecipient)
        .transfer(tokenDistributor.address, parseEther(config.L2_NUM_OF_TOKENS_FOR_CLAIMING))
    ).wait();

    deployedContracts.l2TokenTransferFunds = true;
  }

  return tokenDistributor;
}

async function initTokenDistributor(
  tokenDistributor: TokenDistributor,
  arbDeployer: Signer,
  l2ExecutorAddress: string,
  config: {
    L2_NUM_OF_RECIPIENTS: number;
    L2_NUM_OF_TOKENS_FOR_CLAIMING: string;
    L2_NUM_OF_RECIPIENT_BATCHES_ALREADY_SET: number;
    RECIPIENTS_BATCH_SIZE: number;
    BASE_L2_GAS_PRICE_LIMIT: number;
    BASE_L1_GAS_PRICE_LIMIT: number;
    GET_LOGS_BLOCK_RANGE: number;
  }
) {
  // we store start block when recipient batches are being set
  const previousStartBlock = deployedContracts.distributorSetRecipientsStartBlock;
  if (deployedContracts.distributorSetRecipientsStartBlock == undefined) {
    // store the start block in case we fail
    deployedContracts.distributorSetRecipientsStartBlock =
      await arbDeployer.provider!.getBlockNumber();
  }

  // set claim recipients
  const numOfRecipientsSet = await setClaimRecipients(
    tokenDistributor,
    arbDeployer,
    config,
    previousStartBlock
  );

  // we store end block when all recipients batches are set
  deployedContracts.distributorSetRecipientsEndBlock = await arbDeployer.provider!.getBlockNumber();

  // check num of recipients and claimable amount before transferring ownership
  if (numOfRecipientsSet != config.L2_NUM_OF_RECIPIENTS) {
    throw new Error("Incorrect number of recipients set: " + numOfRecipientsSet);
  }
  const totalClaimable = await tokenDistributor.totalClaimable();
  if (!totalClaimable.eq(parseEther(config.L2_NUM_OF_TOKENS_FOR_CLAIMING))) {
    throw new Error("Incorrect totalClaimable amount of tokenDistributor: " + totalClaimable);
  }

  if (!deployedContracts.l2TokenTransferOwnership) {
    // transfer ownership to L2 UpgradeExecutor
    await (await tokenDistributor.transferOwnership(l2ExecutorAddress)).wait();
    deployedContracts.l2TokenTransferOwnership = true;
  }
}

function readAddresses(): DeployProgressCache {
  if (!fs.existsSync(DEPLOYED_CONTRACTS_FILE_NAME)) return {};
  return JSON.parse(
    fs.readFileSync(DEPLOYED_CONTRACTS_FILE_NAME).toString()
  ) as DeployProgressCache;
}

/**
 * Write addresses of deployed contracts to local JSON file
 */
function writeAddresses() {
  fs.writeFileSync(DEPLOYED_CONTRACTS_FILE_NAME, JSON.stringify(deployedContracts, null, 2));
}

async function main() {
  console.log("Start governance deployment process...");
  deployedContracts = readAddresses();
  console.log(`Cache: ${JSON.stringify(deployedContracts, null, 2)}`);
  try {
    await deployGovernance();
  } finally {
    // write addresses of deployed contracts even when exception is thrown
    console.log("Write deployed contract addresses to deployedContracts.json");
    writeAddresses();
  }
  console.log("Deployment finished!");
}

main().then(() => console.log("Done."));
