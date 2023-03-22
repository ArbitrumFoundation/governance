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
import { Wallet, utils, ContractFactory } from "ethers";
import { JsonRpcProvider } from "@ethersproject/providers";
import fs from "fs";
import { exec } from "child_process";

import dotenv from "dotenv";
dotenv.config();
const abi = utils.defaultAbiCoder;

const l1RPC = process.env.ETH_URL;
const apiKey = process.env.ETHERSCAN_API_KEY;
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
    inbox: "0x",
    govL1Timelock: "0x",
    customGateway: "0x",
    l1GatewayRouter: "",
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

const contractSources: DeployedContracts = {
  l1AddressRegistry:
    "src/gov-action-contracts/address-registries/L1AddressRegistry.sol:L1AddressRegistry",
  pauseInboxAction: "src/gov-action-contracts/pause-inbox/PauseInboxAction.sol:PauseInboxAction",
  unpauseInboxAction:
    "src/gov-action-contracts/pause-inbox/UnpauseInboxAction.sol:UnpauseInboxAction",
  pauseRollupAction: "src/gov-action-contracts/rollup/PauseRollupAction.sol:PauseRollupAction",
  unpauseRollupAction:
    "src/gov-action-contracts/rollup/UnpauseRollupAction.sol:UnpauseRollupAction",
  bridgeRemoveAllOutboxesAction:
    "src/gov-action-contracts/set-outbox/BridgeRemoveAllOutboxesAction.sol:BridgeRemoveAllOutboxesAction",
  bridgeAddOutboxesAction:
    "src/gov-action-contracts/set-outbox/BridgeAddOutboxesAction.sol:BridgeAddOutboxesAction",
  sequencerAddAction:
    "src/gov-action-contracts/sequencer/AddSequencerAction.sol:AddSequencerAction",
  sequencerRemoveAction:
    "src/gov-action-contracts/sequencer/RemoveSequencerAction.sol:RemoveSequencerAction",
};
const verifyWithAddress = async (
  sourceFile: string,
  contractAddress: string,
  chainId: number,
  constructorArgs?: string
) => {
  // avoid rate limiting
  await new Promise((resolve) => setTimeout(resolve, 2000));

  let command = `ETHERSCAN_API_KEY='${apiKey}' forge verify-contract --chain-id ${chainId} --num-of-optimizations 20000 --compiler-version 0.8.16`;
  
  if (constructorArgs) {
    command = `${command} --constructor-args ${constructorArgs}`;
  }
  command = `${command} ${contractAddress} ${sourceFile}`;
  
  console.log('command', command);
  exec(command, (err: Error | null, stdout: string, stderr: string) => {
    console.log("-----------------");
    console.log(command);
    if (err) {
      console.log("Failed to submit for verification", contractAddress, stderr);
    } else {
      console.log("Successfully submitted for verification", contractAddress);
      console.log(stdout);
    }
  });
};

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
  const data = fs.readFileSync(`./files/actions/critical-${l2ChainID}.json`);
  const deploymentData: DeployedContracts = JSON.parse(data.toString());
  for (const [key, value] of Object.entries(deploymentData)) {
    // @ts-ignore
    const source = contractSources[key] as string;
    if (!source) throw new Error(`Missing source`)
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
    await verifyWithAddress(source, value, l2ChainID, constructorArgs);
  }
};

verifyAll()