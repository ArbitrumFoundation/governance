import { Address, L1ToL2MessageStatus, L1TransactionReceipt, L2Network } from "@arbitrum/sdk";
import { Inbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Inbox__factory";
import { L1CustomGateway__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L1CustomGateway__factory";
import { L1GatewayRouter__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L1GatewayRouter__factory";
import { L2CustomGateway__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L2CustomGateway__factory";
import { L2GatewayRouter__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L2GatewayRouter__factory";
import { BigNumber, constants, Contract, ethers, Signer } from "ethers";
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
import {
  DeployProgressCache,
  getDeployersAndConfig as getDeployersAndConfig,
  isDeployingToNova,
  loadDeployedContracts,
  updateDeployedContracts,
} from "./providerSetup";
import { StringProps, TypeChainContractFactoryStatic } from "./testUtils";
import { checkConfigTotals } from "./verifiers";

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
 * /// 12. Rescind factory ownership
 * ///         - transfer ownership of factories to the zero address
 * /// 13. Set executor roles on Nova
 * ///         - call novaUpgradeExecutor.initialize
 * ///         - transfer novaProxyAdmin ownership to upgrade executor
 * /// 14. Register token on ArbOne
 * ///         - register L1 token to ArbOne token mapping on reverse gateways
 * ///         - register L1 token to reverse gateway mapping on Arb routers
 * /// 15. Register token on Nova
 * ///         - register L1 token to Nova token mapping on custom gateways
 * ///         - register L1 token to custom gateway token mapping on Nova routers
 * ///
 * @returns
 */
export const deployGovernance = async () => {
  console.log("Get deployers and signers");
  const {
    ethDeployer,
    arbDeployer,
    novaDeployer,
    deployerConfig,
    arbNetwork,
    novaNetwork,
    claimRecipients,
  } = await getDeployersAndConfig();

  // sanity check the token totals before we start the deployment
  checkConfigTotals(claimRecipients, deployerConfig);

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
      novaDeployer!
    );
    _novaProxyAdmin = novaProxyAdmin;
    _novaUpgradeExecutorProxy = novaUpgradeExecutorProxy;

    console.log("Deploy token to Nova");
    const novaToken = await deployTokenToNova(
      novaDeployer!,
      novaProxyAdmin,
      l1Token,
      novaNetwork!,
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

  console.log("Rescind factory ownership");
  await rescindOwnershipOfFactories(l1GovernanceFactory, l2GovernanceFactory);

  if (isDeployingToNova()) {
    console.log("Set executor roles on Nova");
    await setExecutorRolesOnNova(
      l1DeployResult,
      _novaUpgradeExecutorProxy!,
      _novaProxyAdmin!,
      novaDeployer!,
      deployerConfig
    );
  }

  console.log("Register token on ArbOne");
  await registerTokenOnArbOne(
    l1Token,
    l2DeployResult.token,
    l1ReverseGateway,
    l1DeployResult.executor,
    ethDeployer,
    arbDeployer
  );

  if (isDeployingToNova()) {
    console.log("Register token on Nova");
    await registerTokenOnNova(l1Token, _novaToken!.address, ethDeployer, novaDeployer!);
  }
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
  novaNetwork: L2Network | undefined
) {
  // deploy logic
  const l1TokenLogic = await getOrInitDefault(
    "l1TokenLogic",
    ethDeployer,
    L1ArbitrumToken__factory
  );

  const deadAddress = "0x000000000000000000000000000000000000dEaD";

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
      await proxy.deployed();
      const token = L1ArbitrumToken__factory.connect(proxy.address, ethDeployer);
      await (
        await token.initialize(
          l1ReverseCustomGateway.address,
          isDeployingToNova() ? novaNetwork!.tokenBridge.l1GatewayRouter : deadAddress,
          isDeployingToNova() ? novaNetwork!.tokenBridge.l1CustomGateway : deadAddress,
          // for some intialize fails on a local network without this
          { gasLimit: 300000 }
        )
      ).wait();

      return token;
    }
  );

  await l1Token.deployed();

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
    L2_CORE_QUORUM_THRESHOLD: number;
    L2_TREASURY_QUORUM_THRESHOLD: number;
    L2_PROPOSAL_THRESHOLD: number;
    L2_VOTING_DELAY: number;
    L2_VOTING_PERIOD: number;
    L2_MIN_PERIOD_AFTER_QUORUM: number;
    L2_9_OF_12_SECURITY_COUNCIL: string;
    ARBITRUM_DAO_CONSTITUTION_HASH: string;
    L2_TREASURY_TIMELOCK_DELAY: number;
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
        _coreQuorumThreshold: config.L2_CORE_QUORUM_THRESHOLD,
        _l1Token: l1TokenAddress,
        _treasuryQuorumThreshold: config.L2_TREASURY_QUORUM_THRESHOLD,
        _proposalThreshold: config.L2_PROPOSAL_THRESHOLD,
        _votingDelay: config.L2_VOTING_DELAY,
        _votingPeriod: config.L2_VOTING_PERIOD,
        _minPeriodAfterQuorum: config.L2_MIN_PERIOD_AFTER_QUORUM,
        _l2InitialSupplyRecipient: arbInitialSupplyRecipientAddr,
        _l2EmergencySecurityCouncil: config.L2_9_OF_12_SECURITY_COUNCIL,
        _constitutionHash: config.ARBITRUM_DAO_CONSTITUTION_HASH,
        _l2TreasuryMinTimelockDelay: config.L2_TREASURY_TIMELOCK_DELAY,
      })
    ).wait();

    // get deployed contract addresses
    const l2DeployResult = l2GovDeployReceipt.events?.filter(
      (e) => e.topics[0] === l2GovernanceFactory.interface.getEventTopic("Deployed")
    )[0].args as unknown as L2DeployedEventObject;

    const treasuryTimelock = await L2ArbitrumGovernor__factory.connect(
      l2DeployResult.treasuryGoverner,
      arbDeployer.provider!
    ).timelock();

    // store addresses
    deployedContracts.l2CoreGoverner = l2DeployResult.coreGoverner;
    deployedContracts.l2CoreTimelock = l2DeployResult.coreTimelock;
    deployedContracts.l2Executor = l2DeployResult.executor;
    deployedContracts.l2ProxyAdmin = l2DeployResult.proxyAdmin;
    deployedContracts.l2Token = l2DeployResult.token;
    deployedContracts.l2TreasuryGoverner = l2DeployResult.treasuryGoverner;
    deployedContracts.l2ArbTreasury = l2DeployResult.arbTreasury;
    deployedContracts.arbitrumDAOConstitution = l2DeployResult.arbitrumDAOConstitution;
    deployedContracts.l2TreasuryTimelock = treasuryTimelock;
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

async function rescindOwnershipOfFactories(
  l1GovernanceFactory: L1GovernanceFactory,
  l2GovernanceFactory: L2GovernanceFactory
) {
  const deadAddress = "0x000000000000000000000000000000000000dEaD";
  if ((await l1GovernanceFactory.owner()) !== deadAddress) {
    await (await l1GovernanceFactory.transferOwnership(deadAddress)).wait();
  }

  if ((await l2GovernanceFactory.owner()) !== deadAddress) {
    await (await l2GovernanceFactory.transferOwnership(deadAddress)).wait();
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
  l1Executor: string,
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

  // transfer ownership of L1 reverse gateway to L1 executor
  if (!deployedContracts.registerTokenArbOne3) {
    await (await l1ReverseCustomGateway.connect(ethDeployer).setOwner(l1Executor)).wait();

    deployedContracts.registerTokenArbOne3 = true;
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
  if (!deployedContracts.registerTokenNova) {
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
    const l1ToNovaMsgs = await l1NovaRegistrationTxReceipt.getL1ToL2Messages(
      novaDeployer.provider!
    );

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

    deployedContracts.registerTokenNova = true;
  }
}

// use a global cache
let deployedContracts: DeployProgressCache = {};

async function main() {
  console.log("Start governance deployment process...");
  deployedContracts = loadDeployedContracts();
  console.log(`Cache: ${JSON.stringify(deployedContracts, null, 2)}`);
  try {
    await deployGovernance();
  } finally {
    // write addresses of deployed contracts even when exception is thrown
    console.log("Write deployed contract addresses to deployedContracts.json");
    updateDeployedContracts(deployedContracts);
  }
  console.log("Deployment finished!");
}

process.on('SIGINT', function() {
  console.log("Detected interrupt")
  console.log("Write deployed contract addresses to deployedContracts.json");
  updateDeployedContracts(deployedContracts);
  process.exit();
});

main().then(() => console.log("Done."));
