import {
  L1AddressRegistry__factory,
  PauseInboxAction__factory,
  UnpauseInboxAction,
  UnpauseInboxAction__factory,
  PauseRollupAction__factory,
  UnpauseRollupAction__factory,
  BridgeRemoveAllOutboxesAction__factory,
  BridgeAddOutboxesAction__factory,
  AddSequencerAction__factory,
  RemoveSequencerAction__factory,
} from "../typechain-types";
import { ContractVerifier } from "./contractVerifier";
import { Wallet, utils, ContractFactory } from "ethers";
import { JsonRpcProvider } from "@ethersproject/providers";
import fs from "fs";
import { exec } from "child_process";

import dotenv from "dotenv";
dotenv.config();
const abi = utils.defaultAbiCoder;

const l1RPC = process.env.ETH_URL;
const apiKey = process.env.VERIFY_API_KEY as string;
const l1Key = process.env.ETH_KEY as string;
const l2ChainID = +(process.env.ARB_CHAIN_ID as string);

interface L1RegistryConstructorArgs {
  inbox: string;
  govL1Timelock: string;
  customGateway: string;
  l1GatewayRouter: string;
}

type RegistryArgMamp = {
  [key: number]: L1RegistryConstructorArgs;
};

const chainIdToRegistryAddresses: RegistryArgMamp = {
  41261: {
    inbox: "0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f",
    govL1Timelock: "0xE6841D92B0C345144506576eC13ECf5103aC7f49",
    customGateway: "0xcEe284F754E854890e311e3280b767F80797180d",
    l1GatewayRouter: "0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef",
  },
  412163: {
    inbox: "0x6BEbC4925716945D46F0Ec336D5C2564F419682C",
    govL1Timelock: "0x364188EcF8E0733cB90d8EbeD90d56E56205dDfE",
    customGateway: "0x9fDD1C4E4AA24EEc1d913FABea925594a20d43C7",
    l1GatewayRouter: "0x4c7708168395aEa569453Fc36862D2ffcDaC588c",
  },
  41270: {
    inbox: "0x",
    govL1Timelock: "0x",
    customGateway: "0x",
    l1GatewayRouter: "0x",
  },
};

interface DeployedContracts {
  l1AddressRegistry: string;
  pauseInboxAction: string;
  unpauseInboxAction: string;
  pauseRollupAction: string;
  unpauseRollupAction: string;
  bridgeRemoveAllOutboxesAction: string;
  bridgeAddOutboxesAction: string;
  sequencerAddAction: string;
  sequencerRemoveAction: string;
}

const deployAll = async () => {
  const l1Deployer = new Wallet(l1Key, new JsonRpcProvider(l1RPC));

  const hasBal = (await l1Deployer.getBalance()).gt(0);
  if (!hasBal) {
    throw new Error("L1 deployer has no balance");
  }
  const chainID = await l1Deployer.getChainId();
  if (chainID === 5 && l2ChainID !== 412163) {
    console.log(chainID, l2ChainID);

    throw new Error("L1 / L2 missmatch");
  } else if (chainID === 1 && l2ChainID != 41261 && l2ChainID != 41270) {
    throw new Error("L1 / L2 missmatch");
  }

  const registryConstructorAddresses = chainIdToRegistryAddresses[l2ChainID];
  if (!registryConstructorAddresses) {
    throw new Error("unsupported chain id");
  }

  const connectedL1AddressRegistryFactory = new L1AddressRegistry__factory().connect(l1Deployer);
  console.log(L1AddressRegistry__factory.name);

  const l1AddressRegistry = await connectedL1AddressRegistryFactory.deploy(
    registryConstructorAddresses.inbox,
    registryConstructorAddresses.govL1Timelock,
    registryConstructorAddresses.customGateway,
    registryConstructorAddresses.l1GatewayRouter
  );
  await l1AddressRegistry.deployed();
  const l1RegistryAddress = l1AddressRegistry.address;
  console.log("deployed: L1AddressRegistry", l1RegistryAddress);
  const factories = [
    PauseInboxAction__factory,
    UnpauseInboxAction__factory,
    PauseRollupAction__factory,
    UnpauseRollupAction__factory,
    BridgeRemoveAllOutboxesAction__factory,
    BridgeAddOutboxesAction__factory,
    AddSequencerAction__factory,
    RemoveSequencerAction__factory,
  ];

  const deploymentsAddresses: string[] = [];
  for (let factory of factories) {
    const contractFactory = new factory().connect(l1Deployer);
    const contract = await contractFactory.deploy(l1RegistryAddress);
    await contract.deployed();
    const contractAddress = contract.address;
    console.log("deployed:", factory.name, contractAddress);
    deploymentsAddresses.push(contractAddress);
  }
  console.log(deploymentsAddresses);

  const deployments: DeployedContracts = {
    l1AddressRegistry: l1RegistryAddress,
    pauseInboxAction: deploymentsAddresses[0],
    unpauseInboxAction: deploymentsAddresses[1],
    pauseRollupAction: deploymentsAddresses[2],
    unpauseRollupAction: deploymentsAddresses[3],
    bridgeRemoveAllOutboxesAction: deploymentsAddresses[4],
    bridgeAddOutboxesAction: deploymentsAddresses[5],
    sequencerAddAction: deploymentsAddresses[6],
    sequencerRemoveAction: deploymentsAddresses[7],
  };
  console.log(deployments);

  fs.writeFileSync(`./files/actions/critical-${l2ChainID}.json`, JSON.stringify(deployments));
  return deployments;
};

const verifyAll = async () => {
  const provider = new JsonRpcProvider(l1RPC);
  const chainID = (await provider.getNetwork()).chainId;
  const data = fs.readFileSync(`./files/actions/critical-${l2ChainID}.json`);
  const deploymentData: DeployedContracts = JSON.parse(data.toString());
  const l2Verifier = new ContractVerifier(chainID, apiKey, {});

  for (const [key, value] of Object.entries(deploymentData)) {
    const registryConstructorAddresses = chainIdToRegistryAddresses[l2ChainID];

    const constructorArgs =
      key === "l1AddressesRegistry"
        ? abi.encode(
            ["address", "address", "address", "address"],
            [
              registryConstructorAddresses.inbox,
              registryConstructorAddresses.govL1Timelock,
              registryConstructorAddresses.customGateway,
              registryConstructorAddresses.l1GatewayRouter,
            ]
          )
        : abi.encode(["address"], [deploymentData.l1AddressRegistry]);

    await l2Verifier.verifyWithAddress(key, value, constructorArgs);
  }
};

(async () => {
  await deployAll();
  await verifyAll();
})();
