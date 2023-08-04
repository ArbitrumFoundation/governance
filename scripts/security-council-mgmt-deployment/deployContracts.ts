import {
  L2SecurityCouncilMgmtFactory__factory,
  SecurityCouncilMemberSyncAction__factory,
  L1ArbitrumTimelock__factory,
  IGnosisSafe__factory,
  KeyValueStore__factory,
  ArbitrumEnabledToken__factory,
  SecurityCouncilNomineeElectionGovernor__factory,
  SecurityCouncilMemberElectionGovernor__factory,
  SecurityCouncilManager__factory,
  SecurityCouncilMemberRemovalGovernor__factory,
} from "../../typechain-types";
import {
  DeployParamsStruct,
  SecurityCouncilDataStruct,
  ContractsDeployedEventObject,
  ContractImplementationsStructOutput,
  ContractImplementationsStruct,
} from "../../typechain-types/src/security-council-mgmt/factories/L2SecurityCouncilMgmtFactory";
import { DeploymentConfig, ChainIDToConnectedSigner, UserSpecifiedConfig, ChainConfig } from "./types";
import { JsonRpcProvider, Provider } from "@ethersproject/providers";
import { Wallet, constants } from "ethers";

import { GnosisSafeProxyFactory__factory } from "../../types/ethers-contracts/factories/GnosisSafeProxyFactory__factory";
import { GnosisSafeL2__factory } from "../../types/ethers-contracts/factories/GnosisSafeL2__factory";
import { getL2Network } from "@arbitrum/sdk";

const GNOSIS_SAFE_L2_SINGLETON = "0x3E5c63644E683549055b9Be8653de26E0B4CD36E";
const GNOSIS_SAFE_L1_SINGLETON = "0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552";
const GNOSIS_SAFE_FALLBACK_HANDLER = "0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4";
const GNOSIS_SAFE_FACTORY = "0xa6b71e26c5e0845f74c812102ca7114b6a896ab2";

const EMERGENCY_THRESHOLD = 9;
const NON_EMERGENCY_THRESHOLD = 7;


type SecurityCouncilManagementDeploymentResult = {
  keyValueStores: {[key: number]: string};
  securityCouncilMemberSyncActions: {[key: number]: string};

  emergencyGnosisSafes: {[key: number]: string};
  nonEmergencyGnosisSafe: string;

  nomineeElectionGovernor: string;
  nomineeElectionGovernorLogic: string;
  memberElectionGovernor: string;
  memberElectionGovernorLogic: string;
  securityCouncilManager: string;
  securityCouncilManagerLogic: string;
  securityCouncilMemberRemoverGov: string;
  securityCouncilMemberRemoverGovLogic: string;

  upgradeExecRouteBuilder: string;
}

function randomNonce() {
  return Math.floor(Math.random() * Number.MAX_SAFE_INTEGER);
}

function getSigner(chain: ChainConfig): Wallet {
  return new Wallet(chain.privateKey, new JsonRpcProvider(chain.rpcUrl));
}

async function deployGnosisSafe(singletonAddress: string, owners: string[], threshold: number, nonce: number, signer: Wallet) {
  const factory = GnosisSafeProxyFactory__factory.connect(GNOSIS_SAFE_FACTORY, signer);
  const safeInterface = GnosisSafeL2__factory.createInterface();

  const setupCalldata = safeInterface.encodeFunctionData("setup", [
    owners,
    threshold,
    constants.AddressZero, // to
    "0x", // data
    GNOSIS_SAFE_FALLBACK_HANDLER,
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

async function deploy2(userConfig: UserSpecifiedConfig): Promise<SecurityCouncilManagementDeploymentResult> {
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

  const govChainSigner = getSigner(userConfig.govChain);
  const hostChainSigner = getSigner(userConfig.hostChain);

  // 1. deploy action contracts and key value stores
  const keyValueStores: SecurityCouncilManagementDeploymentResult["keyValueStores"] = {};
  const securityCouncilMemberSyncActions: SecurityCouncilManagementDeploymentResult["securityCouncilMemberSyncActions"] = {};
  for (const chain of allChains) {
    const signer = getSigner(chain);
    const kvStore = await new KeyValueStore__factory(signer).deploy();
    const action = await new SecurityCouncilMemberSyncAction__factory(signer).deploy(kvStore.address);
    keyValueStores[chain.chainID] = kvStore.address;
    securityCouncilMemberSyncActions[chain.chainID] = action.address;
  }

  // 2. deploy gnosis safes
  const owners = await Promise.all([...userConfig.firstCohort, ...userConfig.secondCohort]);
  const emergencyGnosisSafes: SecurityCouncilManagementDeploymentResult["emergencyGnosisSafes"] = {};
  const nonEmergencyGnosisSafe = await deployGnosisSafe(
    GNOSIS_SAFE_L2_SINGLETON,
    owners,
    NON_EMERGENCY_THRESHOLD,
    randomNonce(),
    govChainSigner
  );

  for (const chain of allChains) {
    const signer = getSigner(chain);
    const safe = await deployGnosisSafe(
      chain.chainID === userConfig.hostChain.chainID ? GNOSIS_SAFE_L1_SINGLETON : GNOSIS_SAFE_L2_SINGLETON,
      owners,
      EMERGENCY_THRESHOLD,
      randomNonce(),
      signer
    );
    emergencyGnosisSafes[chain.chainID] = safe;
  }

  // 3. deploy contract implementations (TODO)
  const contractImplementations: ContractImplementationsStruct = {
    nomineeElectionGovernor: (await new SecurityCouncilNomineeElectionGovernor__factory(govChainSigner).deploy()).address,
    memberElectionGovernor: (await new SecurityCouncilMemberElectionGovernor__factory(govChainSigner).deploy()).address,
    securityCouncilManager: (await new SecurityCouncilManager__factory(govChainSigner).deploy()).address,
    securityCouncilMemberRemoverGov: (await new SecurityCouncilMemberRemovalGovernor__factory(govChainSigner).deploy()).address,
  };

  // 4. build deploy params for factory.deploy()
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
  const l2SecurityCouncilMgmtFactory = await new L2SecurityCouncilMgmtFactory__factory(govChainSigner).deploy();

  // 6. call factory.deploy()
  const deployTx = await l2SecurityCouncilMgmtFactory.connect(govChainSigner).deploy(deployParams, contractImplementations);
  const deployReceipt = await deployTx.wait();

  const deployEvent = deployReceipt.events?.filter(
    (e) => e.topics[0] === l2SecurityCouncilMgmtFactory.interface.getEventTopic("ContractsDeployed")
  )[0].args as unknown as ContractsDeployedEventObject;

  if (!deployEvent) throw new Error("No contracts deployed event");

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
//     if (!connectedSigner) throw new Error(`Signer not connected for chain ${chainID}`);
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
