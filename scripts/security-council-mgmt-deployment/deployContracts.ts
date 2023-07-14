import {
  L2SecurityCouncilMgmtFactory__factory,
  SecurityCouncilUpgradeAction__factory,
  L1ArbitrumTimelock__factory,
} from "../../typechain-types";
import {
  DeployParamsStruct,
  SecurityCouncilDataStruct,
  ContractsDeployedEventObject,
} from "../../typechain-types/src/security-council-mgmt/factories/L2SecurityCouncilMgmtFactory";
import { DeploymentConfig } from "./types";

export const deploySecurityCouncilMgmtContracts = async (deploymentConfig: DeploymentConfig) => {
  const { mostDeployParams, securityCouncils, connectedGovChainSigner, l1Provider } =
    deploymentConfig;
  /**
   * TODO up front sanity checks:
   * - all wallets funded
   * - all previously deployed contracts exist
   * - all security councils have the same owners
   */

  const securityCouncilDatas: SecurityCouncilDataStruct[] = [];

  for (let securityCouncilAndSigner of securityCouncils) {
    const { connectedSigner, securityCouncilAddress } = securityCouncilAndSigner;
    const securityCouncilUpgradeAction = await new SecurityCouncilUpgradeAction__factory(
      connectedSigner
    ).deploy();

    securityCouncilDatas.push({
      securityCouncil: securityCouncilAddress,
      chainId: await connectedSigner.getChainId(),
      updateAction: securityCouncilUpgradeAction.address,
    });
  }

  const l2SecurityCouncilMgmtFactory = await new L2SecurityCouncilMgmtFactory__factory(
    connectedGovChainSigner
  ).deploy();

  const l1ArbitrumTimelock = L1ArbitrumTimelock__factory.connect(
    await mostDeployParams.l1ArbitrumTimelock,
    l1Provider
  );
  const l1TimelockMinDelay = l1ArbitrumTimelock.getMinDelay();

  const deployParams: DeployParamsStruct = Object.assign(mostDeployParams, {
    securityCouncils: securityCouncilDatas,
    l1TimelockMinDelay,
  });

  const res = await l2SecurityCouncilMgmtFactory.deploy(deployParams);
  const deployReceipt = await res.wait();

  const l2DeployResult = deployReceipt.events?.filter(
    (e) => e.topics[0] === l2SecurityCouncilMgmtFactory.interface.getEventTopic("ContractsDeployed")
  )[0].args as unknown as ContractsDeployedEventObject;

  const {
    nomineeElectionGovernor,
    memberElectionGovernor,
    securityCouncilManager,
    securityCouncilMemberRemoverGov,
    memberRemovalGovTimelock,
    upgradeExecRouterBuilder,
  } = l2DeployResult.deployedContracts;
  return {
    nomineeElectionGovernor,
    memberElectionGovernor,
    securityCouncilManager,
    securityCouncilMemberRemoverGov,
    memberRemovalGovTimelock,
    upgradeExecRouterBuilder,
    securityCouncilUpgradeActions: securityCouncilDatas.map((data) => {
      return {
        securityCouncilUpgradeAction: data.updateAction,
        chainId: data.chainId,
      };
    }),
  };
};
