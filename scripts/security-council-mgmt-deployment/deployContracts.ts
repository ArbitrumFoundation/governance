import {
  L2SecurityCouncilMgmtFactory__factory,
  SecurityCouncilMemberSyncAction__factory,
  L1ArbitrumTimelock__factory,
  KeyValueStore__factory,
  SecurityCouncilNomineeElectionGovernor__factory,
  SecurityCouncilMemberElectionGovernor__factory,
  SecurityCouncilManager__factory,
  SecurityCouncilMemberRemovalGovernor__factory,
} from "../../typechain-types";
import {
  DeployParamsStruct,
  ContractsDeployedEventObject,
  ContractImplementationsStruct,
} from "../../typechain-types/src/security-council-mgmt/factories/L2SecurityCouncilMgmtFactory";
import { GnosisSafeProxyFactory__factory } from "../../types/ethers-contracts/factories/GnosisSafeProxyFactory__factory";
import { GnosisSafeL2__factory } from "../../types/ethers-contracts/factories/GnosisSafeL2__factory";
import { JsonRpcProvider } from "@ethersproject/providers";
import { getL2Network } from "@arbitrum/sdk";
import { Wallet, constants } from "ethers";
import { DeploymentConfig, ChainConfig, SecurityCouncilManagementDeploymentResult } from "./types";
import { randomNonce } from "./utils";

function getSigner(chain: ChainConfig): Wallet {
  return new Wallet(chain.privateKey, new JsonRpcProvider(chain.rpcUrl));
}

async function deployGnosisSafe(
  singletonAddress: string,
  factoryAddress: string,
  fallbackHandlerAddress: string,
  owners: string[],
  threshold: number,
  nonce: number,
  signer: Wallet
) {
  const factory = GnosisSafeProxyFactory__factory.connect(factoryAddress, signer);
  const safeInterface = GnosisSafeL2__factory.createInterface();

  const setupCalldata = safeInterface.encodeFunctionData("setup", [
    owners,
    threshold,
    constants.AddressZero, // to
    "0x", // data
    fallbackHandlerAddress,
    constants.AddressZero, // payment token
    0, // payment
    constants.AddressZero, // payment receiver
  ]);

  const tx = await factory.createProxyWithNonce(singletonAddress, setupCalldata, nonce);
  
  const receipt = await tx.wait();
  const proxyCreatedEvent = receipt.events?.filter((e) => e.topics[0] === factory.interface.getEventTopic("ProxyCreation"))[0];
  if (!proxyCreatedEvent) throw new Error("No proxy created event");
  const proxyAddress = proxyCreatedEvent.args?.[0];
  return proxyAddress;
}

async function checkChainConfigs(chains: ChainConfig[]) {
  for (const chain of chains) {
    const signer = getSigner(chain);
    const address = await signer.getAddress();
    const balance = await signer.getBalance();
    if (balance.eq(constants.Zero)) throw new Error(`Signer ${address} on ${chain.chainID} not funded`);
    if (chain.chainID !== (await signer.getChainId())) throw new Error(`RPC for ${address} on chain ${chain.chainID} returned wrong chain id`);
  }
}

async function deploy2(userConfig: DeploymentConfig): Promise<SecurityCouncilManagementDeploymentResult> {
  // steps:
  // 1. deploy action contracts and key value stores
  // 2. deploy gnosis safes
  // 3. deploy contract implementations
  // 4. build deploy params for factory.deploy()
  // 5. deploy sc mgmt factory
  // 6. call factory.deploy()

  const allChains = [
    userConfig.hostChain,
    userConfig.govChain,
    ...userConfig.governedChains
  ];

  console.log("Checking chain configs...");
  await checkChainConfigs(allChains);

  const govChainSigner = getSigner(userConfig.govChain);
  const hostChainSigner = getSigner(userConfig.hostChain);

  // 1. deploy action contracts and key value stores
  console.log("Deploying action contracts and key value stores...");

  const keyValueStores: SecurityCouncilManagementDeploymentResult["keyValueStores"] = {};
  const securityCouncilMemberSyncActions: SecurityCouncilManagementDeploymentResult["securityCouncilMemberSyncActions"] = {};

  for (const chain of allChains) {
    const signer = getSigner(chain);

    console.log(`\tDeploying KeyValueStore to chain ${chain.chainID}...`);
    const kvStore = await new KeyValueStore__factory(signer).deploy();

    console.log(`\tDeploying SecurityCouncilMemberSyncAction to chain ${chain.chainID}...`);
    const action = await new SecurityCouncilMemberSyncAction__factory(signer).deploy(kvStore.address);
    keyValueStores[chain.chainID] = kvStore.address;
    securityCouncilMemberSyncActions[chain.chainID] = action.address;
  }

  // 2. deploy gnosis safes
  console.log("Deploying gnosis safes...");

  const owners = await Promise.all([...userConfig.firstCohort, ...userConfig.secondCohort]);
  const emergencyGnosisSafes: SecurityCouncilManagementDeploymentResult["emergencyGnosisSafes"] = {};

  console.log(`\tDeploying non-emergency Gnosis Safe to chain ${userConfig.govChain.chainID}...`);

  const nonEmergencyGnosisSafe = await deployGnosisSafe(
    userConfig.gnosisSafeL2Singleton,
    userConfig.gnosisSafeFactory,
    userConfig.gnosisSafeFallbackHandler,
    owners,
    userConfig.nonEmergencySignerThreshold,
    randomNonce(),
    govChainSigner
  );

  for (const chain of allChains) {
    const signer = getSigner(chain);

    console.log(`\tDeploying emergency Gnosis Safe to chain ${chain.chainID}...`);
    const safe = await deployGnosisSafe(
      chain.chainID === userConfig.hostChain.chainID ? userConfig.gnosisSafeL1Singleton : userConfig.gnosisSafeL2Singleton,
      userConfig.gnosisSafeFactory,
      userConfig.gnosisSafeFallbackHandler,
      owners,
      userConfig.emergencySignerThreshold,
      randomNonce(),
      signer
    );

    emergencyGnosisSafes[chain.chainID] = safe;
  }

  // 3. deploy contract implementations
  console.log("Deploying contract implementations...");

  // temporary object to fill in contract implementations
  const contractImplementationsPartial: Partial<ContractImplementationsStruct> = {};

  console.log(`\tDeploying SecurityCouncilNomineeElectionGovernor to chain ${userConfig.govChain.chainID}...`);
  contractImplementationsPartial.nomineeElectionGovernor = (await new SecurityCouncilNomineeElectionGovernor__factory(govChainSigner).deploy()).address;

  console.log(`\tDeploying SecurityCouncilMemberElectionGovernor to chain ${userConfig.govChain.chainID}...`);
  contractImplementationsPartial.memberElectionGovernor = (await new SecurityCouncilMemberElectionGovernor__factory(govChainSigner).deploy()).address;

  console.log(`\tDeploying SecurityCouncilManager to chain ${userConfig.govChain.chainID}...`);
  contractImplementationsPartial.securityCouncilManager = (await new SecurityCouncilManager__factory(govChainSigner).deploy()).address;

  console.log(`\tDeploying SecurityCouncilMemberRemovalGovernor to chain ${userConfig.govChain.chainID}...`);
  contractImplementationsPartial.securityCouncilMemberRemoverGov = (await new SecurityCouncilMemberRemovalGovernor__factory(govChainSigner).deploy()).address;

  // finished object
  const contractImplementations: ContractImplementationsStruct = contractImplementationsPartial as ContractImplementationsStruct;

  // 4. build deploy params for factory.deploy()
  console.log("Building deploy params for factory.deploy()...");
  const deployParams: DeployParamsStruct = {
    ...userConfig,
    upgradeExecutors: [
      {
        // (L1) host chain executor
        chainId: userConfig.hostChain.chainID,
        location: {
          inbox: constants.AddressZero,
          upgradeExecutor: userConfig.l1Executor,
        },
      },
      {
        // (L2) gov chain executor
        chainId: userConfig.govChain.chainID,
        location: {
          inbox: (await getL2Network(userConfig.govChain.chainID)).ethBridge.inbox,
          upgradeExecutor: userConfig.l1Executor,
        },
      },
      // (L2) governed chain executors
      ...await Promise.all(userConfig.governedChains.map(async (chain) => {
        return {
          chainId: chain.chainID,
          location: {
            inbox: (await getL2Network(chain.chainID)).ethBridge.inbox,
            upgradeExecutor: chain.upExecLocation,
          }
        }
      }))
    ],
    govChainEmergencySecurityCouncil: emergencyGnosisSafes[userConfig.govChain.chainID],
    l1ArbitrumTimelock: userConfig.l1Timelock,
    l2CoreGovTimelock: userConfig.l2CoreTimelock,
    govChainProxyAdmin: userConfig.l2ProxyAdmin,
    l2UpgradeExecutor: userConfig.l2Executor,
    arbToken: userConfig.l2Token,
    l1TimelockMinDelay: L1ArbitrumTimelock__factory.connect(userConfig.l1Timelock, hostChainSigner).getMinDelay(),
    securityCouncils: [
      // emergency councils
      ...allChains.map((chain) => {
        return {
          securityCouncil: emergencyGnosisSafes[chain.chainID],
          chainId: chain.chainID,
          updateAction: securityCouncilMemberSyncActions[chain.chainID],
        }
      }),
      // non-emergency council
      {
        securityCouncil: nonEmergencyGnosisSafe,
        chainId: userConfig.govChain.chainID,
        updateAction: securityCouncilMemberSyncActions[userConfig.govChain.chainID]
      }
    ]
  };

  // 5. deploy sc mgmt factory
  console.log("Deploying sc mgmt factory...");
  const l2SecurityCouncilMgmtFactory = await new L2SecurityCouncilMgmtFactory__factory(govChainSigner).deploy();

  // 6. call factory.deploy()
  console.log("Calling factory.deploy()...");
  const deployTx = await l2SecurityCouncilMgmtFactory.connect(govChainSigner).deploy(deployParams, contractImplementations);
  const deployReceipt = await deployTx.wait();

  const deployEvent = deployReceipt.events?.filter(
    (e) => e.topics[0] === l2SecurityCouncilMgmtFactory.interface.getEventTopic("ContractsDeployed")
  )[0].args as unknown as ContractsDeployedEventObject;

  if (!deployEvent) throw new Error("No contracts deployed event");

  console.log("Done!");

  return {
    keyValueStores,
    securityCouncilMemberSyncActions,
    emergencyGnosisSafes,
    nonEmergencyGnosisSafe,
    nomineeElectionGovernor: deployEvent.deployedContracts.nomineeElectionGovernor,
    nomineeElectionGovernorLogic: await contractImplementations.nomineeElectionGovernor,
    memberElectionGovernor: deployEvent.deployedContracts.memberElectionGovernor,
    memberElectionGovernorLogic: await contractImplementations.memberElectionGovernor,
    securityCouncilManager: deployEvent.deployedContracts.securityCouncilManager,
    securityCouncilManagerLogic: await contractImplementations.securityCouncilManager,
    securityCouncilMemberRemoverGov: deployEvent.deployedContracts.securityCouncilMemberRemoverGov,
    securityCouncilMemberRemoverGovLogic: await contractImplementations.securityCouncilMemberRemoverGov,
    upgradeExecRouteBuilder: deployEvent.deployedContracts.upgradeExecRouteBuilder,
  }
}



import config from "./configs/mainnet2";

deploy2(config).then((res) => {
  console.log(res);
});























// export const deploySecurityCouncilMgmtContracts = async (deploymentConfig: DeploymentConfig) => {
//   const { mostDeployParams, securityCouncils, chainIDs } = deploymentConfig;

//   if (!process.env.ARB_KEY) throw new Error("need ARB_KEY");
//   if (!process.env.ETH_KEY) throw new Error("need ETH_KEY");

//   // set up signers
//   const govChainSigner = new Wallet(process.env.ARB_KEY, new JsonRpcProvider(process.env.ARB_URL));
//   const govChainID = await govChainSigner.getChainId();

//   if (govChainID != chainIDs.govChainID)
//     throw new Error(`connected to wrong gov chain: ${govChainID}, expected ${chainIDs.govChainID}`);

//   const l1Signer = new Wallet(process.env.ETH_KEY, new JsonRpcProvider(process.env.ETH_URL));
//   const l1ChainID = await l1Signer.getChainId();

//   if (l1ChainID != chainIDs.l1ChainID)
//     throw new Error(`connected to wrong l1 chain: ${l1ChainID}, expected ${chainIDs.l1ChainID}`);

//   const chainIDToConnectedSigner: ChainIDToConnectedSigner = {
//     [l1ChainID]: l1Signer,
//     [govChainID]: govChainSigner,
//   };

//   if (process.env.NOVA_KEY && process.env.NOVA_URL) {
//     const novaSigner = new Wallet(process.env.NOVA_KEY, new JsonRpcProvider(process.env.NOVA_URL));
//     const novaChainID = await novaSigner.getChainId();
//     chainIDToConnectedSigner[novaChainID] = novaSigner;
//   }

//   // pre deployment checks
//   await sanityChecks(
//     deploymentConfig,
//     govChainSigner.provider,
//     l1Signer.provider,
//     chainIDToConnectedSigner
//   );

//   // deploy action contracts
//   const securityCouncilDatas: SecurityCouncilDataStruct[] = [];

//   for (let securityCouncilAndSigner of securityCouncils) {
//     const { chainID, securityCouncilAddress } = securityCouncilAndSigner;

//     const connectedSigner = chainIDToConnectedSigner[chainID];
//     if (!connectedSigner) throw new Error(`Signer not connected to chain ${chainID}`);
//     const securityCouncilUpgradeAction = await new SecurityCouncilMemberSyncAction__factory(
//       connectedSigner
//     ).deploy();

//     securityCouncilDatas.push({
//       securityCouncil: securityCouncilAddress,
//       chainId: await connectedSigner.getChainId(),
//       updateAction: securityCouncilUpgradeAction.address,
//     });
//   }

//   // deploy sc mgmt
//   const l2SecurityCouncilMgmtFactory = await new L2SecurityCouncilMgmtFactory__factory(
//     govChainSigner
//   ).deploy();

//   const l1ArbitrumTimelock = L1ArbitrumTimelock__factory.connect(
//     await mostDeployParams.l1ArbitrumTimelock,
//     l1Signer.provider
//   );
//   const l1TimelockMinDelay = l1ArbitrumTimelock.getMinDelay();

//   const deployParams: DeployParamsStruct = Object.assign(mostDeployParams, {
//     securityCouncils: securityCouncilDatas,
//     l1TimelockMinDelay,
//   });

//   const res = await l2SecurityCouncilMgmtFactory.deploy(deployParams);
//   const deployReceipt = await res.wait();

//   const l2DeployResult = deployReceipt.events?.filter(
//     (e) => e.topics[0] === l2SecurityCouncilMgmtFactory.interface.getEventTopic("ContractsDeployed")
//   )[0].args as unknown as ContractsDeployedEventObject;

//   const {
//     nomineeElectionGovernor,
//     memberElectionGovernor,
//     securityCouncilManager,
//     securityCouncilMemberRemoverGov,
//     memberRemovalGovTimelock,
//     UpgradeExecRouteBuilder,
//   } = l2DeployResult.deployedContracts;
//   return {
//     nomineeElectionGovernor,
//     memberElectionGovernor,
//     securityCouncilManager,
//     securityCouncilMemberRemoverGov,
//     memberRemovalGovTimelock,
//     UpgradeExecRouteBuilder,
//     securityCouncilUpgradeActions: securityCouncilDatas.map((data) => {
//       return {
//         securityCouncilUpgradeAction: data.updateAction,
//         chainId: data.chainId,
//       };
//     }),
//   };
// };

// const sanityChecks = async (
//   deploymentConfig: DeploymentConfig,
//   govChainProvider: Provider,
//   l1Provider: Provider,
//   chainIDToConnectedSigner: ChainIDToConnectedSigner
// ) => {
//   // ensure all signers funded
//   for (let chainIdStr in Object.keys(chainIDToConnectedSigner)) {
//     const signer = chainIDToConnectedSigner[+chainIdStr];
//     if (await (await signer.getBalance()).gt(constants.Zero)) {
//       const address = await signer.getAddress();
//       throw new Error(`Signer ${address} on ${chainIdStr} not funded`);
//     }
//   }

//   // ensure all security councils have the same owners

//   const allScOwners: string[][] = [];

//   for (let scData of deploymentConfig.securityCouncils) {
//     const signer = chainIDToConnectedSigner[scData.chainID];
//     if (!signer) throw new Error(`No provider found for ${scData.chainID}`);

//     const safe = IGnosisSafe__factory.connect(scData.securityCouncilAddress, signer);
//     const owners = await safe.getOwners();
//     allScOwners.push(owners);
//   }
//   const ownersStr = allScOwners[0].sort().join(",");
//   for (let i = 1; i < allScOwners.length; i++) {
//     const currentOwnersStr = allScOwners[i].sort().join(",");
//     if (ownersStr != currentOwnersStr)
//       throw new Error(`Security council owners not equal: ${ownersStr} vs ${currentOwnersStr}`);
//   }
//   /**
//    * TODO ensure all previously deployed contracts (have deployed bytecode)
//    */
// };
