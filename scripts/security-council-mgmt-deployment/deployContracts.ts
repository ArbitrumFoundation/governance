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
import { GnosisSafeL2__factory } from "../../types/ethers-contracts/factories/GnosisSafeL2__factory";
import { JsonRpcProvider } from "@ethersproject/providers";
import { getL2Network } from "@arbitrum/sdk";
import { BigNumber, Wallet, constants, ethers } from "ethers";
import { DeploymentConfig, ChainConfig, SecurityCouncilManagementDeploymentResult, GovernedChainConfig } from "./types";
import { randomNonce } from "./utils";
import { SafeFactory, EthersAdapter } from '@safe-global/protocol-kit'

function getSigner(chain: ChainConfig): Wallet {
  return new Wallet(chain.privateKey, new JsonRpcProvider(chain.rpcUrl));
}

// deploy gnosis safe with a module and set of owners
async function deployGnosisSafe(
  owners: string[],
  threshold: number,
  module: string,
  nonce: number,
  signer: Wallet
) {
  const ethAdapter = new EthersAdapter({ ethers, signerOrProvider: signer })
  const safeFactory = await SafeFactory.create({ ethAdapter })

  const safeSdk = await safeFactory.deploySafe({ 
    safeAccountConfig: {
      owners: [...owners, signer.address],
      threshold: 1
    }, 
    saltNonce: nonce.toString() 
  });

  let addDeployerAsModuleTx = await safeSdk.createTransaction({
    safeTransactionData: {
      to: await safeSdk.getAddress(),
      value: "0",
      data: (await safeSdk.createEnableModuleTx(signer.address)).data.data,
    }
  });
  addDeployerAsModuleTx = await safeSdk.signTransaction(addDeployerAsModuleTx);

  const addDeployerAsModuleTxResult = await safeSdk.executeTransaction(addDeployerAsModuleTx);
  await addDeployerAsModuleTxResult.transactionResponse?.wait();

  // make sure the deployer is a module
  if (!await safeSdk.isModuleEnabled(signer.address)) {
    throw new Error("Deployer is not a module");
  }

  // remove the deployer as an owner and set threshold 
  let removeDeployerAsOwnerTx = await safeSdk.createTransaction({
    safeTransactionData: {
      to: await safeSdk.getAddress(),
      value: "0",
      data: (await safeSdk.createRemoveOwnerTx({ ownerAddress: signer.address, threshold })).data.data,
    }
  });
  removeDeployerAsOwnerTx = await safeSdk.signTransaction(removeDeployerAsOwnerTx);

  const removeDeployerAsOwnerTxResult = await safeSdk.executeTransaction(removeDeployerAsOwnerTx);
  await removeDeployerAsOwnerTxResult.transactionResponse?.wait();

  // make sure the deployer is not an owner
  if (await safeSdk.isOwner(signer.address)) {
    throw new Error("Deployer is still an owner");
  }

  // make sure the threshold is correct
  if (await safeSdk.getThreshold() !== threshold) {
    throw new Error("Threshold is not correct");
  }

  const safe = GnosisSafeL2__factory.connect(await safeSdk.getAddress(), signer);

  // add the intended module
  const addModuleTx = await safe.execTransactionFromModule(
    safe.address,
    0,
    (await safeSdk.createEnableModuleTx(module)).data.data,
    0 // operation = call
  );
  await addModuleTx.wait();

  // make sure the module is enabled
  if (!await safeSdk.isModuleEnabled(module)) {
    throw new Error("Module is not enabled");
  }

  // remove the deployer as a module
  const removeDeployerAsModuleTx = await safe.execTransactionFromModule(
    safe.address, 
    0, 
    (await safeSdk.createDisableModuleTx(signer.address)).data.data,
    0 // operation = call
  );
  await removeDeployerAsModuleTx.wait();

  // make sure the deployer is not a module
  if (await safeSdk.isModuleEnabled(signer.address)) {
    throw new Error("Deployer is still a module");
  }

  return safe.address;
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

  // 1. deploy action contracts and key value stores
  console.log("Deploying action contracts and key value stores...");

  const keyValueStores: SecurityCouncilManagementDeploymentResult["keyValueStores"] = {};
  const securityCouncilMemberSyncActions: SecurityCouncilManagementDeploymentResult["securityCouncilMemberSyncActions"] = {};

  for (const chain of allChains) {
    const signer = getSigner(chain);

    console.log(`\tDeploying KeyValueStore to chain ${chain.chainID}...`);
    const kvStore = await new KeyValueStore__factory(signer).deploy();
    await kvStore.deployed();

    console.log(`\tDeploying SecurityCouncilMemberSyncAction to chain ${chain.chainID}...`);

    const action = await new SecurityCouncilMemberSyncAction__factory(signer).deploy(kvStore.address);
    await action.deployed();

    keyValueStores[chain.chainID] = kvStore.address;
    securityCouncilMemberSyncActions[chain.chainID] = action.address;
  }

  // 2. deploy gnosis safes
  console.log("Deploying gnosis safes...");

  const owners = await Promise.all([...config.firstCohort, ...config.secondCohort]);
  const emergencyGnosisSafes: SecurityCouncilManagementDeploymentResult["emergencyGnosisSafes"] = {};

  console.log(`\tDeploying non-emergency Gnosis Safe to chain ${config.govChain.chainID}...`);

  const nonEmergencyGnosisSafe = await deployGnosisSafe(
    owners,
    config.nonEmergencySignerThreshold,
    config.l2Executor,
    randomNonce(),
    govChainSigner
  );

  for (const chain of allChains) {
    const signer = getSigner(chain);

    let executor;
    switch (chain.chainID) {
      case config.hostChain.chainID:
        executor = config.l1Executor;
        break;
      case config.govChain.chainID:
        executor = config.l2Executor;
        break;
      default:
        executor = (chain as GovernedChainConfig).upExecLocation;
    }

    console.log(`\tDeploying emergency Gnosis Safe to chain ${chain.chainID}...`);
    const safe = await deployGnosisSafe(
      owners,
      config.emergencySignerThreshold,
      executor,
      randomNonce(),
      signer
    );

    emergencyGnosisSafes[chain.chainID] = safe;
  }

  // 3. deploy contract implementations
  console.log("Deploying contract implementations...");

  console.log(`\tDeploying SecurityCouncilNomineeElectionGovernor to chain ${config.govChain.chainID}...`);
  const nomineeElectionGovernor = await new SecurityCouncilNomineeElectionGovernor__factory(govChainSigner).deploy();
  await nomineeElectionGovernor.deployed();

  console.log(`\tDeploying SecurityCouncilMemberElectionGovernor to chain ${config.govChain.chainID}...`);
  const memberElectionGovernor = await new SecurityCouncilMemberElectionGovernor__factory(govChainSigner).deploy();
  await memberElectionGovernor.deployed();

  console.log(`\tDeploying SecurityCouncilManager to chain ${config.govChain.chainID}...`);
  const securityCouncilManager = await new SecurityCouncilManager__factory(govChainSigner).deploy();
  await securityCouncilManager.deployed();

  console.log(`\tDeploying SecurityCouncilMemberRemovalGovernor to chain ${config.govChain.chainID}...`);
  const securityCouncilMemberRemoverGov = await new SecurityCouncilMemberRemovalGovernor__factory(govChainSigner).deploy();
  await securityCouncilMemberRemoverGov.deployed();

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
          upgradeExecutor: config.l2Executor,
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
  // some additional config checks
  if(BigNumber.from(await config.firstNominationStartDate.day).toNumber() > 28
    && BigNumber.from(await config.firstNominationStartDate.month).toNumber() === 8) {
      // Next election would be on undefined date in february
    throw new Error("Invalid date for first nomination start date. Please choose a date that is not the 29th, 30th, or 31st of August.")
  }
  if(new Set(await Promise.all((config.firstCohort).concat(config.secondCohort))).size !== 12) {
    throw new Error("Invalid cohort. Please ensure that all addresses are unique.")
  }

  // 5. deploy sc mgmt factory
  console.log("Deploying sc mgmt factory...");
  const l2SecurityCouncilMgmtFactory = await new L2SecurityCouncilMgmtFactory__factory(govChainSigner).deploy();
  await l2SecurityCouncilMgmtFactory.deployed();

  // 6. call factory.deploy()
  console.log("Calling factory.deploy()...");
  const deployTx = await l2SecurityCouncilMgmtFactory.connect(govChainSigner).deploy(deployParams, contractImplementations);
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
    config.l2AddressRegistry
  );
  await govChainActivationAction.deployed();
  activationActionContracts[config.govChain.chainID] = govChainActivationAction.address;

  // 7b. deploy activation action contract to host chain
  console.log(`\tDeploying activation action contract to host chain ${config.hostChain.chainID}...`);
  const hostChainActivationAction = await new L1SCMgmtActivationAction__factory(hostChainSigner).deploy(
    emergencyGnosisSafes[config.hostChain.chainID],
    config.hostChain.prevEmergencySecurityCouncil,
    config.emergencySignerThreshold,
    config.l1Executor,
    config.l1Timelock
  );
  await hostChainActivationAction.deployed();
  activationActionContracts[config.hostChain.chainID] = hostChainActivationAction.address;

  // 7c. deploy activation action contract to governed chains
  for (const chain of config.governedChains) {
    console.log(`\tDeploying activation action contract to governed chain ${chain.chainID}...`);
    const signer = getSigner(chain);
    const activationAction = await new NonGovernanceChainSCMgmtActivationAction__factory(signer).deploy(
      emergencyGnosisSafes[chain.chainID],
      chain.prevEmergencySecurityCouncil,
      config.emergencySignerThreshold,
      chain.upExecLocation
    );
    await activationAction.deployed();
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
