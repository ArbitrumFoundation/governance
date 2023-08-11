import {
  L2SecurityCouncilMgmtFactory__factory,
  SecurityCouncilMemberSyncAction__factory,
  L1ArbitrumTimelock__factory,
  KeyValueStore__factory,
  SecurityCouncilNomineeElectionGovernor__factory,
  SecurityCouncilMemberElectionGovernor__factory,
  SecurityCouncilManager__factory,
  SecurityCouncilMemberRemovalGovernor__factory,
  GovernanceChainSCMgmtActivationAction__factory,
  L1SCMgmtActivationAction__factory,
  NonGovernanceChainSCMgmtActivationAction__factory,
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
import { Overrides, Wallet, constants } from "ethers";
import { DeploymentConfig, ChainConfig, SecurityCouncilManagementDeploymentResult } from "./types";
import { randomNonce } from "./utils";
import { PromiseOrValue } from "../../typechain-types/common";

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
  signer: Wallet,
  overrides?: Overrides & { from?: PromiseOrValue<string> }
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

  const tx = await factory.createProxyWithNonce(singletonAddress, setupCalldata, nonce, overrides);
  
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

export async function deployContracts(config: DeploymentConfig): Promise<SecurityCouncilManagementDeploymentResult> {
  // steps:
  // 1. deploy action contracts and key value stores
  // 2. deploy gnosis safes
  // 3. deploy contract implementations
  // 4. build deploy params for factory.deploy()
  // 5. deploy sc mgmt factory
  // 6. call factory.deploy()

  const allChains = [
    config.hostChain,
    config.govChain,
    ...config.governedChains
  ];

  console.log("Checking chain configs...");
  await checkChainConfigs(allChains);

  const govChainSigner = getSigner(config.govChain);
  const hostChainSigner = getSigner(config.hostChain);

  // keep track of account nonces because ethers isn't doing this
  console.log("Getting nonces...");
  const nonces: {[key: number]: number} = {};
  for (const chain of allChains) {
    nonces[chain.chainID] = await getSigner(chain).getTransactionCount();
  }

  // 1. deploy action contracts and key value stores
  console.log("Deploying action contracts and key value stores...");

  const keyValueStores: SecurityCouncilManagementDeploymentResult["keyValueStores"] = {};
  const securityCouncilMemberSyncActions: SecurityCouncilManagementDeploymentResult["securityCouncilMemberSyncActions"] = {};

  for (const chain of allChains) {
    const signer = getSigner(chain);

    console.log(`\tDeploying KeyValueStore to chain ${chain.chainID}...`);
    const kvStore = await new KeyValueStore__factory(signer).deploy({ nonce: nonces[chain.chainID]++ });
    await kvStore.deployTransaction.wait();

    console.log(`\tDeploying SecurityCouncilMemberSyncAction to chain ${chain.chainID}...`);
    
    const action = await new SecurityCouncilMemberSyncAction__factory(signer).deploy(kvStore.address, { nonce: nonces[chain.chainID]++ });
    await action.deployTransaction.wait();

    keyValueStores[chain.chainID] = kvStore.address;
    securityCouncilMemberSyncActions[chain.chainID] = action.address;
  }

  // 2. deploy gnosis safes
  console.log("Deploying gnosis safes...");

  const owners = await Promise.all([...config.firstCohort, ...config.secondCohort]);
  const emergencyGnosisSafes: SecurityCouncilManagementDeploymentResult["emergencyGnosisSafes"] = {};

  console.log(`\tDeploying non-emergency Gnosis Safe to chain ${config.govChain.chainID}...`);

  const nonEmergencyGnosisSafe = await deployGnosisSafe(
    config.gnosisSafeL2Singleton,
    config.gnosisSafeFactory,
    config.gnosisSafeFallbackHandler,
    owners,
    config.nonEmergencySignerThreshold,
    randomNonce(),
    govChainSigner,
    { nonce: nonces[config.govChain.chainID]++ }
  );

  for (const chain of allChains) {
    const signer = getSigner(chain);

    console.log(`\tDeploying emergency Gnosis Safe to chain ${chain.chainID}...`);
    const safe = await deployGnosisSafe(
      chain.chainID === config.hostChain.chainID ? config.gnosisSafeL1Singleton : config.gnosisSafeL2Singleton,
      config.gnosisSafeFactory,
      config.gnosisSafeFallbackHandler,
      owners,
      config.emergencySignerThreshold,
      randomNonce(),
      signer,
      { nonce: nonces[chain.chainID]++ }
    );

    emergencyGnosisSafes[chain.chainID] = safe;
  }

  // 3. deploy contract implementations
  console.log("Deploying contract implementations...");

  console.log(`\tDeploying SecurityCouncilNomineeElectionGovernor to chain ${config.govChain.chainID}...`);
  const nomineeElectionGovernor = await new SecurityCouncilNomineeElectionGovernor__factory(govChainSigner).deploy(
    { nonce: nonces[config.govChain.chainID]++ }
  );
  nomineeElectionGovernor.deployTransaction.wait();

  console.log(`\tDeploying SecurityCouncilMemberElectionGovernor to chain ${config.govChain.chainID}...`);
  const memberElectionGovernor = await new SecurityCouncilMemberElectionGovernor__factory(govChainSigner).deploy(
    { nonce: nonces[config.govChain.chainID]++ }
  );
  memberElectionGovernor.deployTransaction.wait();

  console.log(`\tDeploying SecurityCouncilManager to chain ${config.govChain.chainID}...`);
  const securityCouncilManager = await new SecurityCouncilManager__factory(govChainSigner).deploy(
    { nonce: nonces[config.govChain.chainID]++ }
  );
  securityCouncilManager.deployTransaction.wait();

  console.log(`\tDeploying SecurityCouncilMemberRemovalGovernor to chain ${config.govChain.chainID}...`);
  const securityCouncilMemberRemoverGov = await new SecurityCouncilMemberRemovalGovernor__factory(govChainSigner).deploy(
    { nonce: nonces[config.govChain.chainID]++ }
  );
  securityCouncilMemberRemoverGov.deployTransaction.wait();

  // finished object
  const contractImplementations: ContractImplementationsStruct = {
    nomineeElectionGovernor: nomineeElectionGovernor.address,
    memberElectionGovernor: memberElectionGovernor.address,
    securityCouncilManager: securityCouncilManager.address,
    securityCouncilMemberRemoverGov: securityCouncilMemberRemoverGov.address,
  };

  // 4. build deploy params for factory.deploy()
  console.log("Building deploy params for factory.deploy()...");
  const deployParams: DeployParamsStruct = {
    ...config,
    upgradeExecutors: [
      {
        // (L1) host chain executor
        chainId: config.hostChain.chainID,
        location: {
          inbox: constants.AddressZero,
          upgradeExecutor: config.l1Executor,
        },
      },
      {
        // (L2) gov chain executor
        chainId: config.govChain.chainID,
        location: {
          inbox: (await getL2Network(config.govChain.chainID)).ethBridge.inbox,
          upgradeExecutor: config.l1Executor,
        },
      },
      // (L2) governed chain executors
      ...await Promise.all(config.governedChains.map(async (chain) => {
        return {
          chainId: chain.chainID,
          location: {
            inbox: (await getL2Network(chain.chainID)).ethBridge.inbox,
            upgradeExecutor: chain.upExecLocation,
          }
        }
      }))
    ],
    govChainEmergencySecurityCouncil: emergencyGnosisSafes[config.govChain.chainID],
    l1ArbitrumTimelock: config.l1Timelock,
    l2CoreGovTimelock: config.l2CoreTimelock,
    govChainProxyAdmin: config.l2ProxyAdmin,
    l2UpgradeExecutor: config.l2Executor,
    arbToken: config.l2Token,
    l1TimelockMinDelay: L1ArbitrumTimelock__factory.connect(config.l1Timelock, hostChainSigner).getMinDelay(),
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
        chainId: config.govChain.chainID,
        updateAction: securityCouncilMemberSyncActions[config.govChain.chainID]
      }
    ]
  };

  // 5. deploy sc mgmt factory
  console.log("Deploying sc mgmt factory...");
  const l2SecurityCouncilMgmtFactory = await new L2SecurityCouncilMgmtFactory__factory(govChainSigner).deploy(
    { nonce: nonces[config.govChain.chainID]++ }
  );
  await l2SecurityCouncilMgmtFactory.deployTransaction.wait();

  // 6. call factory.deploy()
  console.log("Calling factory.deploy()...");
  const deployTx = await l2SecurityCouncilMgmtFactory.connect(govChainSigner).deploy(
    deployParams, 
    contractImplementations, 
    { nonce: nonces[config.govChain.chainID]++ }
  );
  const deployReceipt = await deployTx.wait();

  const deployEvent = deployReceipt.events?.filter(
    (e) => e.topics[0] === l2SecurityCouncilMgmtFactory.interface.getEventTopic("ContractsDeployed")
  )[0].args as unknown as ContractsDeployedEventObject;

  if (!deployEvent) throw new Error("No contracts deployed event");

  // 7. deploy activation action contracts
  console.log("Deploying activation action contracts...");
  const activationActionContracts: SecurityCouncilManagementDeploymentResult["activationActionContracts"] = {};

  // 7a. deploy activation action contract to gov chain
  console.log(`\tDeploying activation action contract to governance chain ${config.govChain.chainID}...`);
  const govChainActivationAction = await new GovernanceChainSCMgmtActivationAction__factory(govChainSigner).deploy(
    emergencyGnosisSafes[config.govChain.chainID],
    nonEmergencyGnosisSafe,
    config.govChain.prevEmergencySecurityCouncil,
    config.govChain.prevNonEmergencySecurityCouncil,
    config.emergencySignerThreshold,
    config.nonEmergencySignerThreshold,
    deployEvent.deployedContracts.securityCouncilManager,
    config.l2AddressRegistry,
    { nonce: nonces[config.govChain.chainID]++ }
  );
  govChainActivationAction.deployTransaction.wait();
  activationActionContracts[config.govChain.chainID] = govChainActivationAction.address;

  // 7b. deploy activation action contract to host chain
  console.log(`\tDeploying activation action contract to host chain ${config.hostChain.chainID}...`);
  const hostChainActivationAction = await new L1SCMgmtActivationAction__factory(hostChainSigner).deploy(
    emergencyGnosisSafes[config.hostChain.chainID],
    config.hostChain.prevEmergencySecurityCouncil,
    config.emergencySignerThreshold,
    config.l1Executor,
    config.l1Timelock,
    { nonce: nonces[config.hostChain.chainID]++ }
  );
  hostChainActivationAction.deployTransaction.wait();
  activationActionContracts[config.hostChain.chainID] = hostChainActivationAction.address;

  // 7c. deploy activation action contract to governed chains
  for (const chain of config.governedChains) {
    console.log(`\tDeploying activation action contract to governed chain ${chain.chainID}...`);
    const signer = getSigner(chain);
    const activationAction = await new NonGovernanceChainSCMgmtActivationAction__factory(signer).deploy(
      emergencyGnosisSafes[chain.chainID],
      chain.prevEmergencySecurityCouncil,
      config.emergencySignerThreshold,
      chain.upExecLocation,
      { nonce: nonces[chain.chainID]++ }
    );
    activationAction.deployTransaction.wait();
    activationActionContracts[chain.chainID] = activationAction.address;
  }

  return {
    activationActionContracts,
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
    l2SecurityCouncilMgmtFactory: l2SecurityCouncilMgmtFactory.address,
  }
}
