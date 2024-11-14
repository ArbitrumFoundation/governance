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
import { IOwnable__factory } from "../../token-bridge-contracts/build/types";

dotenv.config();

export const deployGovernance = async () => {
  // load env vars
  const parentChainRpc = process.env["PARENT_CHAIN_RPC"] as string;
  const parentChainDeployKey = process.env["PARENT_CHAIN_DEPLOY_KEY"] as string;
  const childChainRpc = process.env["CHILD_CHAIN_RPC"] as string;
  const childChainDeployKey = process.env["CHILD_CHAIN_DEPLOY_KEY"] as string;
  const inboxAddress = process.env["INBOX_ADDRESS"] as string;
  const tokenBridgeCreatorAddress = process.env["TOKEN_BRIDGE_CREATOR_ADDRESS"] as string;
  if (
    ![
      parentChainRpc,
      parentChainDeployKey,
      childChainRpc,
      childChainDeployKey,
      inboxAddress,
      tokenBridgeCreatorAddress,
    ].every(Boolean)
  ) {
    throw new Error(
      "Following env vars have to be set: PARENT_CHAIN_RPC, PARENT_CHAIN_DEPLOY_KEY, CHILD_CHAIN_RPC, CHILD_CHAIN_DEPLOY_KEY, INBOX_ADDRESS, TOKEN_BRIDGE_CREATOR_ADDRESS"
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
  console.log("GovernanceToken: ", governanceToken.address);

  // get deployment data
  const { childChainUpExec, childChainProxyAdmin, parentChainUpExec, parentChainProxyAdmin } =
    await getDeploymentData(
      parentChainDeployerWallet.provider!,
      inboxAddress,
      tokenBridgeCreatorAddress
    );

  /// step1
  const deploymentReceipt = await (
    await childChainFactory.deployStep1({
      _governanceToken: governanceToken.address,
      _govChainUpExec: childChainUpExec,
      _govChainProxyAdmin: childChainProxyAdmin,
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
  const { coreTimelock: _childChainCoreTimelock, coreGoverner: _childChainCoreGov } =
    _getParsedLogs(deploymentReceipt.logs, childChainFactory.interface, "Deployed")[0].args;
  const _minTimelockDelay = 7;

  await (
    await parentChainFactory.deployStep2(
      parentChainUpExec,
      parentChainProxyAdmin,
      inboxAddress,
      _childChainCoreTimelock,
      _minTimelockDelay
    )
  ).wait();
  console.log("Step2 finished");
};

async function getDeploymentData(
  parentChainProvider: Provider,
  inboxAddress: string,
  tokenBridgeCreatorAddress: string
) {
  /// get child chain deployment data
  const tokenBridgeCreator = new ethers.Contract(
    tokenBridgeCreatorAddress,
    tokenBridgeCreatorABI,
    parentChainProvider
  );
  const [, , , , , childChainProxyAdmin, , childChainUpExec, ,] =
    await tokenBridgeCreator.inboxToL2Deployment(inboxAddress);

  /// get parent chain info
  const bridge = await IInbox__factory.connect(inboxAddress, parentChainProvider).bridge();
  const rollup = await IBridge__factory.connect(bridge, parentChainProvider).rollup();
  const parentChainUpExec = await IOwnable__factory.connect(rollup, parentChainProvider).owner();
  const iinboxProxyAdmin = new ethers.Contract(
    inboxAddress,
    iinboxProxyAdminABI,
    parentChainProvider
  );
  const parentChainProxyAdmin = await iinboxProxyAdmin.getProxyAdmin();

  let data = {
    childChainUpExec,
    childChainProxyAdmin,
    parentChainUpExec,
    parentChainProxyAdmin,
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

//// subset of token bridge creator ABI
const tokenBridgeCreatorABI = [
  {
    inputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    name: "inboxToL1Deployment",
    outputs: [
      {
        internalType: "address",
        name: "router",
        type: "address",
      },
      {
        internalType: "address",
        name: "standardGateway",
        type: "address",
      },
      {
        internalType: "address",
        name: "customGateway",
        type: "address",
      },
      {
        internalType: "address",
        name: "wethGateway",
        type: "address",
      },
      {
        internalType: "address",
        name: "weth",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    name: "inboxToL2Deployment",
    outputs: [
      {
        internalType: "address",
        name: "router",
        type: "address",
      },
      {
        internalType: "address",
        name: "standardGateway",
        type: "address",
      },
      {
        internalType: "address",
        name: "customGateway",
        type: "address",
      },
      {
        internalType: "address",
        name: "wethGateway",
        type: "address",
      },
      {
        internalType: "address",
        name: "weth",
        type: "address",
      },
      {
        internalType: "address",
        name: "proxyAdmin",
        type: "address",
      },
      {
        internalType: "address",
        name: "beaconProxyFactory",
        type: "address",
      },
      {
        internalType: "address",
        name: "upgradeExecutor",
        type: "address",
      },
      {
        internalType: "address",
        name: "multicall",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
];

const iinboxProxyAdminABI = [
  {
    inputs: [],
    name: "getProxyAdmin",
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
