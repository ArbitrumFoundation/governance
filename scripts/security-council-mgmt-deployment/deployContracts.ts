import {
  L2SecurityCouncilMgmtFactory__factory,
  SecurityCouncilUpgradeAction__factory,
  L1ArbitrumTimelock__factory,
  IGnosisSafe__factory,
} from "../../typechain-types";
import {
  DeployParamsStruct,
  SecurityCouncilDataStruct,
  ContractsDeployedEventObject,
} from "../../typechain-types/src/security-council-mgmt/factories/L2SecurityCouncilMgmtFactory";
import { DeploymentConfig, ChainIDToConnectedSigner } from "./types";
import { JsonRpcProvider, Provider } from "@ethersproject/providers";
import { Wallet, constants } from "ethers";

export const deploySecurityCouncilMgmtContracts = async (deploymentConfig: DeploymentConfig) => {
  const { mostDeployParams, securityCouncils, chainIDs } = deploymentConfig;

  if (!process.env.ARB_KEY) throw new Error("need ARB_KEY");
  if (!process.env.ETH_KEY) throw new Error("need ETH_KEY");

  // set up signers
  const govChainSigner = new Wallet(process.env.ARB_KEY, new JsonRpcProvider(process.env.ARB_URL));
  const govChainID = await govChainSigner.getChainId();

  if (govChainID != chainIDs.govChainID)
    throw new Error(`connected to wrong gov chain: ${govChainID}, expected ${chainIDs.govChainID}`);

  const l1Signer = new Wallet(process.env.ETH_KEY, new JsonRpcProvider(process.env.ETH_URL));
  const l1ChainID = await l1Signer.getChainId();

  if (l1ChainID != chainIDs.l1ChainID)
    throw new Error(`connected to wrong l1 chain: ${l1ChainID}, expected ${chainIDs.l1ChainID}`);

  const chainIDToConnectedSigner: ChainIDToConnectedSigner = {
    [l1ChainID]: l1Signer,
    [govChainID]: govChainSigner,
  };

  if (process.env.NOVA_KEY && process.env.NOVA_URL) {
    const novaSigner = new Wallet(process.env.NOVA_KEY, new JsonRpcProvider(process.env.NOVA_URL));
    const novaChainID = await novaSigner.getChainId();
    chainIDToConnectedSigner[novaChainID] = novaSigner;
  }

  // pre deployment checks
  await sanityChecks(
    deploymentConfig,
    govChainSigner.provider,
    l1Signer.provider,
    chainIDToConnectedSigner
  );

  // deploy action contracts
  const securityCouncilDatas: SecurityCouncilDataStruct[] = [];

  for (let securityCouncilAndSigner of securityCouncils) {
    const { chainID, securityCouncilAddress } = securityCouncilAndSigner;

    const connectedSigner = chainIDToConnectedSigner[chainID];
    if (!connectedSigner) throw new Error(`Signer not connected for chain ${chainID}`);
    const securityCouncilUpgradeAction = await new SecurityCouncilUpgradeAction__factory(
      connectedSigner
    ).deploy();

    securityCouncilDatas.push({
      securityCouncil: securityCouncilAddress,
      chainId: await connectedSigner.getChainId(),
      updateAction: securityCouncilUpgradeAction.address,
    });
  }

  // deploy sc mgmt
  const l2SecurityCouncilMgmtFactory = await new L2SecurityCouncilMgmtFactory__factory(
    govChainSigner
  ).deploy();

  const l1ArbitrumTimelock = L1ArbitrumTimelock__factory.connect(
    await mostDeployParams.l1ArbitrumTimelock,
    l1Signer.provider
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

const sanityChecks = async (
  deploymentConfig: DeploymentConfig,
  govChainProvider: Provider,
  l1Provider: Provider,
  chainIDToConnectedSigner: ChainIDToConnectedSigner
) => {
  // ensure all signers funded
  for (let chainIdStr in Object.keys(chainIDToConnectedSigner)) {
    const signer = chainIDToConnectedSigner[+chainIdStr];
    if (await (await signer.getBalance()).gt(constants.Zero)) {
      const address = await signer.getAddress();
      throw new Error(`Signer ${address} on ${chainIdStr} not funded`);
    }
  }

  // ensure all security councils have the same owners

  const allScOwners: string[][] = [];

  for (let scData of deploymentConfig.securityCouncils) {
    const signer = chainIDToConnectedSigner[scData.chainID];
    if (!signer) throw new Error(`No provider found for ${scData.chainID}`);

    const safe = IGnosisSafe__factory.connect(scData.securityCouncilAddress, signer);
    const owners = await safe.getOwners();
    allScOwners.push(owners);
  }
  const ownersStr = allScOwners[0].sort().join(",");
  for (let i = 1; i < allScOwners.length; i++) {
    const currentOwnersStr = allScOwners[i].sort().join(",");
    if (ownersStr != currentOwnersStr)
      throw new Error(`Security council owners not equal: ${ownersStr} vs ${currentOwnersStr}`);
  }
  /**
   * TODO ensure all previously deployed contracts (have deployed bytecode)
   */
};
