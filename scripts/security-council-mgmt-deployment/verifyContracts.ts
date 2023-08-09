import { GovernanceChainSCMgmtActivationAction__factory, ISecurityCouncilMemberElectionGovernor__factory, KeyValueStore__factory, L1SCMgmtActivationAction__factory, L2SecurityCouncilMgmtFactory__factory, NonGovernanceChainSCMgmtActivationAction__factory, SecurityCouncilManager__factory, SecurityCouncilMemberElectionGovernor__factory, SecurityCouncilMemberRemovalGovernor__factory, SecurityCouncilMemberSyncAction__factory, SecurityCouncilNomineeElectionGovernor__factory, TransparentUpgradeableProxy__factory, UpgradeExecRouteBuilder__factory } from "../../typechain-types";
import { ContractVerificationConfig, verifyContract, verifyContracts } from "../minimalContractVerifier";
import { promises as fs} from "fs";
import { SecurityCouncilManagementDeploymentResult } from "./types";
import mainnetConfig from "./configs/mainnet";
import goerliConfig from "./configs/arbgoerli";
import { assertDefined } from "./utils";
import { ethers } from "ethers";

// todo: replace with cli option
const TESTNET = true;

const apiKeys = {
  eth: assertDefined(process.env.ETHERSCAN_API_KEY),
  arb: assertDefined(process.env.ARBISCAN_API_KEY),
  nova: assertDefined(process.env.NOVA_ARBISCAN_API_KEY)
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
  const config = TESTNET ? goerliConfig : mainnetConfig;

  // going in order of scmDeployment

  // first do activation contracts
  const activationContractConfigs: ContractVerificationConfig[] = [
    {
      // gov chain activation contract
      factory: new GovernanceChainSCMgmtActivationAction__factory(),
      contractName: "GovernanceChainSCMgmtActivationAction",
      chainId: config.govChain.chainID,
      address: scmDeployment.activationActionContracts[config.govChain.chainID],
      constructorArgs: [
        scmDeployment.emergencyGnosisSafes[config.govChain.chainID],
        scmDeployment.nonEmergencyGnosisSafe,
        config.govChain.prevEmergencySecurityCouncil,
        config.govChain.prevNonEmergencySecurityCouncil,
        config.emergencySignerThreshold,
        config.nonEmergencySignerThreshold,
        scmDeployment.securityCouncilManager,
        config.l2AddressRegistry
      ],
      foundryProfile: "sec_council_mgmt",
      etherscanApiKey: chainIdToApiKey[config.govChain.chainID]
    },
    {
      // host chain activation contract
      factory: new L1SCMgmtActivationAction__factory(),
      contractName: "L1SCMgmtActivationAction",
      chainId: config.hostChain.chainID,
      address: scmDeployment.activationActionContracts[config.hostChain.chainID],
      constructorArgs: [
        scmDeployment.emergencyGnosisSafes[config.hostChain.chainID],
        config.hostChain.prevEmergencySecurityCouncil,
        config.emergencySignerThreshold,
        config.l1Executor,
        config.l1Timelock
      ],
      foundryProfile: "sec_council_mgmt",
      etherscanApiKey: chainIdToApiKey[config.hostChain.chainID]
    },
    // governed chains activation contracts
    ...config.governedChains.map((chain) => ({
      factory: new NonGovernanceChainSCMgmtActivationAction__factory(),
      contractName: "NonGovernanceChainSCMgmtActivationAction",
      chainId: chain.chainID,
      address: scmDeployment.activationActionContracts[chain.chainID],
      constructorArgs: [
        scmDeployment.emergencyGnosisSafes[chain.chainID],
        chain.prevEmergencySecurityCouncil,
        config.emergencySignerThreshold,
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
    chainId: config.govChain.chainID,
    address: scmDeployment.nomineeElectionGovernorLogic,
    constructorArgs: [],
    foundryProfile: "sec_council_mgmt",
    etherscanApiKey: chainIdToApiKey[config.govChain.chainID]
  };

  // nominee election gov proxy (only need to verify one since they all have same deployed bytecode)
  const nomineeElectionGovProxyConfig: ContractVerificationConfig = {
    factory: new TransparentUpgradeableProxy__factory(),
    contractName: "TransparentUpgradeableProxy",
    chainId: config.govChain.chainID,
    address: scmDeployment.nomineeElectionGovernor,
    constructorArgs: [
      scmDeployment.nomineeElectionGovernorLogic,
      config.l2ProxyAdmin,
      []
    ],
    foundryProfile: "sec_council_mgmt",
    etherscanApiKey: chainIdToApiKey[config.govChain.chainID]
  };

  // member election gov logic
  const memberElectionGovConfig: ContractVerificationConfig = {
    factory: new SecurityCouncilMemberElectionGovernor__factory(),
    contractName: "SecurityCouncilMemberElectionGovernor",
    chainId: config.govChain.chainID,
    address: scmDeployment.memberElectionGovernorLogic,
    constructorArgs: [],
    foundryProfile: "sec_council_mgmt",
    etherscanApiKey: chainIdToApiKey[config.govChain.chainID]
  };

  // manager logic
  const managerConfig: ContractVerificationConfig = {
    factory: new SecurityCouncilManager__factory(),
    contractName: "SecurityCouncilManager",
    chainId: config.govChain.chainID,
    address: scmDeployment.securityCouncilManagerLogic,
    constructorArgs: [],
    foundryProfile: "sec_council_mgmt",
    etherscanApiKey: chainIdToApiKey[config.govChain.chainID]
  };

  // removal gov logic
  const removalGovConfig: ContractVerificationConfig = {
    factory: new SecurityCouncilMemberRemovalGovernor__factory(),
    contractName: "SecurityCouncilMemberRemovalGovernor",
    chainId: config.govChain.chainID,
    address: scmDeployment.securityCouncilMemberRemoverGovLogic,
    constructorArgs: [],
    foundryProfile: "sec_council_mgmt",
    etherscanApiKey: chainIdToApiKey[config.govChain.chainID]
  };

  // skip route builder since the factory deploys it

  // factory
  const factoryConfig: ContractVerificationConfig = {
    factory: new L2SecurityCouncilMgmtFactory__factory(),
    contractName: "L2SecurityCouncilMgmtFactory",
    chainId: config.govChain.chainID,
    address: scmDeployment.l2SecurityCouncilMgmtFactory,
    constructorArgs: [],
    foundryProfile: "sec_council_mgmt",
    etherscanApiKey: chainIdToApiKey[config.govChain.chainID]
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
    factoryConfig
  ];

  await verifyContracts(allConfigs);
}

main().then(() => console.log("Done.")).catch((err) => {
  console.error(err);
  process.exit(1);
});