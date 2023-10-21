import { Wallet, ethers } from "ethers";
import {
  GovernanceChainGovFactory__factory,
  IBridge__factory,
  IInbox__factory,
  ParentChainGovFactory__factory,
  WrappedNativeGovToken__factory,
} from "../../typechain-types";
import { Filter, JsonRpcProvider, Provider } from "@ethersproject/providers";
import { execSync } from "child_process";

import dotenv from "dotenv";
import { Interface } from "@ethersproject/abi";
import { RollupCore__factory } from "@arbitrum/sdk/dist/lib/abi/factories/RollupCore__factory";
dotenv.config();

export const deployGovernance = async () => {
  // load env vars
  const parentChainRpc = process.env["PARENT_CHAIN_RPC"] as string;
  const parentChainDeployKey = process.env["PARENT_CHAIN_DEPLOY_KEY"] as string;
  const childChainRpc = process.env["CHILD_CHAIN_RPC"] as string;
  const childChainDeployKey = process.env["CHILD_CHAIN_DEPLOY_KEY"] as string;
  if (![parentChainRpc, parentChainDeployKey, childChainRpc, childChainDeployKey].every(Boolean)) {
    throw new Error(
      "Following env vars have to be set: PARENT_CHAIN_RPC, PARENT_CHAIN_DEPLOY_KEY, CHILD_CHAIN_RPC, CHILD_CHAIN_DEPLOY_KEY"
    );
  }

  // deploy parent chain governance factory
  const parentChainDeployerWallet = new Wallet(parentChainDeployKey).connect(
    new JsonRpcProvider(parentChainRpc)
  );
  const parentChainFactoryFac = await new ParentChainGovFactory__factory(
    parentChainDeployerWallet
  ).deploy();
  const parentChainFactory = await parentChainFactoryFac.deployed();
  console.log("ParentChainGovFactory: ", parentChainFactory.address);

  // deploy child chain governance factory
  const childChainDeployerWallet = new Wallet(childChainDeployKey).connect(
    new JsonRpcProvider(childChainRpc)
  );
  const childChainFactoryFac = await new GovernanceChainGovFactory__factory(
    childChainDeployerWallet
  ).deploy();
  const childChainFactory = await childChainFactoryFac.deployed();
  console.log("GovernanceChainGov: ", childChainFactory.address);

  // deploy governance token
  const governanceTokenFac = await new WrappedNativeGovToken__factory(
    childChainDeployerWallet
  ).deploy();
  const governanceToken = await governanceTokenFac.deployed();

  // get deployment data
  const rollupData = await getDeploymentData(parentChainDeployerWallet.provider!);

  /// step1
  const deploymentReceipt = await (
    await childChainFactory.deployStep1({
      _governanceToken: governanceToken.address,
      _govChainUpExec: rollupData.childChainUpgradeExecutor,
      _govChainProxyAdmin: rollupData.childChainUpgradeExecutor,
      _proposalThreshold: 100,
      _votingPeriod: 10,
      _votingDelay: 10,
      _minTimelockDelay: 7,
      _minPeriodAfterQuorum: 1,
      _coreQuorumThreshold: 500,
    })
  ).wait();
  console.log("Step1 finished");

  //// step 2
  const _parentChainUpExec = rollupData["upgrade-executor"];
  const _parentChainProxyAdmin = rollupData.parentChainProxyAdmin;
  const _inbox = rollupData.inbox;
  const { coreTimelock: _childChainCoreTimelock, coreGoverner: _childChainCoreGov } =
    _getParsedLogs(deploymentReceipt.logs, childChainFactory.interface, "Deployed")[0].args;
  const _minTimelockDelay = 7;

  await (
    await parentChainFactory.deployStep2(
      _parentChainUpExec,
      _parentChainProxyAdmin,
      _inbox,
      _childChainCoreTimelock,
      _minTimelockDelay
    )
  ).wait();
  console.log("Step2 finished");
};

async function getDeploymentData(parentChainProvider: Provider) {
  /// get rollup data from config file
  let sequencerContainer = execSync('docker ps --filter "name=l3node" --format "{{.Names}}"')
    .toString()
    .trim();
  const deploymentData = execSync(
    `docker exec ${sequencerContainer} cat /config/l3deployment.json`
  ).toString();
  const parsedDeploymentData = JSON.parse(deploymentData) as {
    bridge: string;
    inbox: string;
    ["sequencer-inbox"]: string;
    rollup: string;
    ["native-token"]: string;
    ["upgrade-executor"]: string;
  };

  //// get parent chain deployment data
  const filter: Filter = {
    topics: [
      ethers.utils.id(
        "OrbitTokenBridgeCreated(address,address,address,address,address,address,address,address)"
      ),
      ethers.utils.hexZeroPad(parsedDeploymentData.inbox, 32),
    ],
  };
  const logs = await parentChainProvider.getLogs({
    ...filter,
    fromBlock: 0,
    toBlock: "latest",
  });
  if (logs.length === 0) {
    throw new Error("Couldn't find any OrbitTokenBridgeCreated events in block range[0,latest]");
  }
  const eventIface = new Interface(eventABI);
  const parentChainDeploymentData = eventIface.parseLog(logs[0]);

  ///// get child chain deployment data
  const rollup = await IBridge__factory.connect(
    await IInbox__factory.connect(parsedDeploymentData.inbox, parentChainProvider).bridge(),
    parentChainProvider
  ).rollup();
  const chainId = await RollupCore__factory.connect(rollup, parentChainProvider).chainId();

  const tokenBridgeCreatorAddress = logs[0].address;
  const tokenBridgeCreator = new ethers.Contract(
    tokenBridgeCreatorAddress,
    tokenBridgeCreatorABI,
    parentChainProvider
  );
  const childChainUpgradeExecutor = await tokenBridgeCreator.getCanonicalL2UpgradeExecutorAddress(
    chainId
  );
  const childChainProxyAdmin = await tokenBridgeCreator.getCanonicalL2ProxyAdminAddress(chainId);

  let data = {
    ...parsedDeploymentData,
    parentChainInbox: parsedDeploymentData.inbox,
    parentChainProxyAdmin: parentChainDeploymentData.args.proxyAdmin,
    parentChainRouter: parentChainDeploymentData.args.router,
    parentChainStandardGateway: parentChainDeploymentData.args.standardGateway,
    parentChainCustomGateway: parentChainDeploymentData.args.customGateway,
    childChainUpgradeExecutor: childChainUpgradeExecutor,
    childChainProxyAdmin: childChainProxyAdmin,
  };

  return data;
}

export const _getParsedLogs = (
  logs: ethers.providers.Log[],
  iface: ethers.utils.Interface,
  eventName: string
) => {
  const eventFragment = iface.getEvent(eventName);
  const parsedLogs = logs
    .filter((curr: any) => curr.topics[0] === iface.getEventTopic(eventFragment))
    .map((curr: any) => iface.parseLog(curr));
  return parsedLogs;
};

//// OrbitTokenBridgeCreated event ABI
const eventABI = [
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "inbox",
        type: "address",
      },
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "address",
        name: "router",
        type: "address",
      },
      {
        indexed: false,
        internalType: "address",
        name: "standardGateway",
        type: "address",
      },
      {
        indexed: false,
        internalType: "address",
        name: "customGateway",
        type: "address",
      },
      {
        indexed: false,
        internalType: "address",
        name: "wethGateway",
        type: "address",
      },
      {
        indexed: false,
        internalType: "address",
        name: "proxyAdmin",
        type: "address",
      },
      {
        indexed: false,
        internalType: "address",
        name: "upgradeExecutor",
        type: "address",
      },
    ],
    name: "OrbitTokenBridgeCreated",
    type: "event",
  },
];

//// subset of token bridge creator ABI
const tokenBridgeCreatorABI = [
  {
    inputs: [
      {
        internalType: "uint256",
        name: "chainId",
        type: "uint256",
      },
    ],
    name: "getCanonicalL2UpgradeExecutorAddress",
    outputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "chainId",
        type: "uint256",
      },
    ],
    name: "getCanonicalL2ProxyAdminAddress",
    outputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
];

async function main() {
  console.log("Start governance deployment process...");
  await deployGovernance();
  console.log("Deployment finished!");
}

main().then(() => console.log("Done."));
