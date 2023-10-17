import { GovernanceChainSCMgmtActivationAction__factory, ISecurityCouncilMemberElectionGovernor__factory, KeyValueStore__factory, L1ArbitrumTimelock__factory, L1SCMgmtActivationAction__factory, L2SecurityCouncilMgmtFactory__factory, NonGovernanceChainSCMgmtActivationAction__factory, SecurityCouncilManager__factory, SecurityCouncilMemberElectionGovernor__factory, SecurityCouncilMemberRemovalGovernor__factory, SecurityCouncilMemberSyncAction__factory, SecurityCouncilNomineeElectionGovernor__factory, TransparentUpgradeableProxy__factory, UpgradeExecRouteBuilder__factory } from "../../typechain-types";
import { ContractVerificationConfig, verifyContracts } from "../minimalContractVerifier";
import { promises as fs} from "fs";
import { SecurityCouncilManagementDeploymentResult } from "./types";
import mainnetConfig from "./configs/mainnet";
import goerliConfig from "./configs/arbgoerli";
import { assertDefined } from "./utils";
import { getL2Network } from "@arbitrum/sdk";
import { JsonRpcProvider } from "@ethersproject/providers";
import { ethers } from "ethers";

const TESTNET = true;

const apiKeys = {
  eth: assertDefined(process.env.ETHERSCAN_API_KEY, "ETHERSCAN_API_KEY undefined"),
  arb: assertDefined(process.env.ARBISCAN_API_KEY, "ARBISCAN_API_KEY undefined"),
  nova: assertDefined(process.env.NOVA_ARBISCAN_API_KEY, "NOVA_ARBISCAN_API_KEY undefined")
};

const chainIdToApiKey: {[key: number]: string} = {
  1: apiKeys.eth,
  5: apiKeys.eth,
  42161: apiKeys.arb,
  421613: apiKeys.arb,
  42170: apiKeys.nova
};

async function main() {
  const path = TESTNET ? "files/goerli/scmDeployment.json" : "files/mainnet/scmDeployment.json";
  const scmDeployment = JSON.parse((await fs.readFile(path)).toString()) as SecurityCouncilManagementDeploymentResult;
  const deploymentConfig = TESTNET ? goerliConfig : mainnetConfig;

  // going in order of scmDeployment

  // first do activation contracts
  const activationContractConfigs: ContractVerificationConfig[] = [
    {
      // gov chain activation contract
      factory: new GovernanceChainSCMgmtActivationAction__factory(),
      contractName: "GovernanceChainSCMgmtActivationAction",
      chainId: deploymentConfig.govChain.chainID,
      address: scmDeployment.activationActionContracts[deploymentConfig.govChain.chainID],
      constructorArgs: [
        scmDeployment.emergencyGnosisSafes[deploymentConfig.govChain.chainID],
        scmDeployment.nonEmergencyGnosisSafe,
        deploymentConfig.govChain.prevEmergencySecurityCouncil,
        deploymentConfig.govChain.prevNonEmergencySecurityCouncil,
        deploymentConfig.emergencySignerThreshold,
        deploymentConfig.nonEmergencySignerThreshold,
        scmDeployment.securityCouncilManager,
        deploymentConfig.l2AddressRegistry
      ],
      foundryProfile: "sec_council_mgmt",
      etherscanApiKey: chainIdToApiKey[deploymentConfig.govChain.chainID]
    },
    {
      // host chain activation contract
      factory: new L1SCMgmtActivationAction__factory(),
      contractName: "L1SCMgmtActivationAction",
      chainId: deploymentConfig.hostChain.chainID,
      address: scmDeployment.activationActionContracts[deploymentConfig.hostChain.chainID],
      constructorArgs: [
        scmDeployment.emergencyGnosisSafes[deploymentConfig.hostChain.chainID],
        deploymentConfig.hostChain.prevEmergencySecurityCouncil,
        deploymentConfig.emergencySignerThreshold,
        deploymentConfig.l1Executor,
        deploymentConfig.l1Timelock
      ],
      foundryProfile: "sec_council_mgmt",
      etherscanApiKey: chainIdToApiKey[deploymentConfig.hostChain.chainID]
    },
    // governed chains activation contracts
    ...deploymentConfig.governedChains.map((chain) => ({
      factory: new NonGovernanceChainSCMgmtActivationAction__factory(),
      contractName: "NonGovernanceChainSCMgmtActivationAction",
      chainId: chain.chainID,
      address: scmDeployment.activationActionContracts[chain.chainID],
      constructorArgs: [
        scmDeployment.emergencyGnosisSafes[chain.chainID],
        chain.prevEmergencySecurityCouncil,
        deploymentConfig.emergencySignerThreshold,
        chain.upExecLocation
      ],
      foundryProfile: "sec_council_mgmt",
      etherscanApiKey: chainIdToApiKey[chain.chainID]
    }))
  ];

  // key value stores
  const keyValueStoreConfigs: ContractVerificationConfig[] = Object.keys(scmDeployment.keyValueStores).map((chainIdStr) => {
    const chainId = parseInt(chainIdStr);
    return {
      factory: new KeyValueStore__factory(),
      contractName: "KeyValueStore",
      chainId,
      address: scmDeployment.keyValueStores[chainId],
      constructorArgs: [],
      foundryProfile: "sec_council_mgmt",
      etherscanApiKey: chainIdToApiKey[chainId]
    }
  });

  // member sync actions
  const memberSyncActionConfigs: ContractVerificationConfig[] = Object.keys(scmDeployment.securityCouncilMemberSyncActions).map((chainIdStr) => {
    const chainId = parseInt(chainIdStr);
    return {
      factory: new SecurityCouncilMemberSyncAction__factory(),
      contractName: "SecurityCouncilMemberSyncAction",
      chainId,
      address: scmDeployment.securityCouncilMemberSyncActions[chainId],
      constructorArgs: [
        scmDeployment.keyValueStores[chainId]
      ],
      foundryProfile: "sec_council_mgmt",
      etherscanApiKey: chainIdToApiKey[chainId]
    }
  });

  // skip gnosis safes

  // nominee election gov logic
  const nomineeElectionGovConfig: ContractVerificationConfig = {
    factory: new SecurityCouncilNomineeElectionGovernor__factory(),
    contractName: "SecurityCouncilNomineeElectionGovernor",
    chainId: deploymentConfig.govChain.chainID,
    address: scmDeployment.nomineeElectionGovernorLogic,
    constructorArgs: [],
    foundryProfile: "sec_council_mgmt",
    etherscanApiKey: chainIdToApiKey[deploymentConfig.govChain.chainID]
  };

  // nominee election gov proxy (only need to verify one proxy since they all have same deployed bytecode)
  const nomineeElectionGovProxyConfig: ContractVerificationConfig = {
    factory: new TransparentUpgradeableProxy__factory(),
    contractName: "TransparentUpgradeableProxy",
    chainId: deploymentConfig.govChain.chainID,
    address: scmDeployment.nomineeElectionGovernor,
    constructorArgs: [
      scmDeployment.nomineeElectionGovernorLogic,
      deploymentConfig.l2ProxyAdmin,
      []
    ],
    foundryProfile: "sec_council_mgmt",
    etherscanApiKey: chainIdToApiKey[deploymentConfig.govChain.chainID]
  };

  // member election gov logic
  const memberElectionGovConfig: ContractVerificationConfig = {
    factory: new SecurityCouncilMemberElectionGovernor__factory(),
    contractName: "SecurityCouncilMemberElectionGovernor",
    chainId: deploymentConfig.govChain.chainID,
    address: scmDeployment.memberElectionGovernorLogic,
    constructorArgs: [],
    foundryProfile: "sec_council_mgmt",
    etherscanApiKey: chainIdToApiKey[deploymentConfig.govChain.chainID]
  };

  // manager logic
  const managerConfig: ContractVerificationConfig = {
    factory: new SecurityCouncilManager__factory(),
    contractName: "SecurityCouncilManager",
    chainId: deploymentConfig.govChain.chainID,
    address: scmDeployment.securityCouncilManagerLogic,
    constructorArgs: [],
    foundryProfile: "sec_council_mgmt",
    etherscanApiKey: chainIdToApiKey[deploymentConfig.govChain.chainID]
  };

  // removal gov logic
  const removalGovConfig: ContractVerificationConfig = {
    factory: new SecurityCouncilMemberRemovalGovernor__factory(),
    contractName: "SecurityCouncilMemberRemovalGovernor",
    chainId: deploymentConfig.govChain.chainID,
    address: scmDeployment.securityCouncilMemberRemoverGovLogic,
    constructorArgs: [],
    foundryProfile: "sec_council_mgmt",
    etherscanApiKey: chainIdToApiKey[deploymentConfig.govChain.chainID]
  };

  // route builder
  const routeBuilderConfig: ContractVerificationConfig = {
    factory: new UpgradeExecRouteBuilder__factory(),
    contractName: "UpgradeExecRouteBuilder",
    chainId: deploymentConfig.govChain.chainID,
    address: scmDeployment.upgradeExecRouteBuilder,
    constructorArgs: [
      [
        {
          // (L1) host chain executor
          chainId: deploymentConfig.hostChain.chainID,
          location: {
            inbox: ethers.constants.AddressZero,
            upgradeExecutor: deploymentConfig.l1Executor,
          },
        },
        {
          // (L2) gov chain executor
          chainId: deploymentConfig.govChain.chainID,
          location: {
            inbox: (await getL2Network(deploymentConfig.govChain.chainID)).ethBridge.inbox,
            upgradeExecutor: deploymentConfig.l2Executor,
          },
        },
        // (L2) governed chain executors
        ...await Promise.all(deploymentConfig.governedChains.map(async (chain) => {
          return {
            chainId: chain.chainID,
            location: {
              inbox: (await getL2Network(chain.chainID)).ethBridge.inbox,
              upgradeExecutor: chain.upExecLocation,
            }
          }
        }))
      ],
      deploymentConfig.l1Timelock,
      await L1ArbitrumTimelock__factory.connect(deploymentConfig.l1Timelock, new JsonRpcProvider(assertDefined(process.env.ETH_URL))).getMinDelay()
    ],
    foundryProfile: "sec_council_mgmt",
    etherscanApiKey: chainIdToApiKey[deploymentConfig.govChain.chainID]
  };

  // factory
  const factoryConfig: ContractVerificationConfig = {
    factory: new L2SecurityCouncilMgmtFactory__factory(),
    contractName: "L2SecurityCouncilMgmtFactory",
    chainId: deploymentConfig.govChain.chainID,
    address: scmDeployment.l2SecurityCouncilMgmtFactory,
    constructorArgs: [],
    foundryProfile: "sec_council_mgmt",
    etherscanApiKey: chainIdToApiKey[deploymentConfig.govChain.chainID]
  };

  const allConfigs = [
    ...activationContractConfigs, 
    ...keyValueStoreConfigs,
    ...memberSyncActionConfigs,
    nomineeElectionGovConfig,
    nomineeElectionGovProxyConfig,
    memberElectionGovConfig,
    managerConfig,
    removalGovConfig,
    factoryConfig,
    routeBuilderConfig
  ];

  await verifyContracts(allConfigs);
}

main().then(() => console.log("Done.")).catch((err) => {
  console.error(err);
  process.exit(1);
});