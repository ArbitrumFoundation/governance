import {
  envVars,
  getDeployersAndConfig,
  getProviders,
  isDeployingToNova,
  isLocalDeployment,
} from "./providerSetup";
import { ethers, Wallet } from "ethers";
import fs from "fs";
import { getProxyOwner } from "./testUtils";
import { ProxyAdmin__factory } from "../typechain-types";
import { execSync } from "child_process";
import { L2Network } from "@arbitrum/sdk";
import { Provider } from "@ethersproject/providers";
import {
  L1CustomGateway__factory,
  L1GatewayRouter__factory,
} from "../token-bridge-contracts/build/types";
import { GnosisBatch } from "./prepareProtocolOwnershipTransfer";

export const ARB_OWNER_PRECOMPILE = "0x0000000000000000000000000000000000000070";

// This is the v1.1 abi, TODO: import upgrade-executor from the new repo
const upgradeExecutorAbi = '[{"inputs":[],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint8","name":"version","type":"uint8"}],"name":"Initialized","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"bytes32","name":"role","type":"bytes32"},{"indexed":true,"internalType":"bytes32","name":"previousAdminRole","type":"bytes32"},{"indexed":true,"internalType":"bytes32","name":"newAdminRole","type":"bytes32"}],"name":"RoleAdminChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"bytes32","name":"role","type":"bytes32"},{"indexed":true,"internalType":"address","name":"account","type":"address"},{"indexed":true,"internalType":"address","name":"sender","type":"address"}],"name":"RoleGranted","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"bytes32","name":"role","type":"bytes32"},{"indexed":true,"internalType":"address","name":"account","type":"address"},{"indexed":true,"internalType":"address","name":"sender","type":"address"}],"name":"RoleRevoked","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"target","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"},{"indexed":false,"internalType":"bytes","name":"data","type":"bytes"}],"name":"TargetCallExecuted","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"upgrade","type":"address"},{"indexed":false,"internalType":"uint256","name":"value","type":"uint256"},{"indexed":false,"internalType":"bytes","name":"data","type":"bytes"}],"name":"UpgradeExecuted","type":"event"},{"inputs":[],"name":"ADMIN_ROLE","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"DEFAULT_ADMIN_ROLE","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"EXECUTOR_ROLE","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"upgrade","type":"address"},{"internalType":"bytes","name":"upgradeCallData","type":"bytes"}],"name":"execute","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"address","name":"target","type":"address"},{"internalType":"bytes","name":"targetCallData","type":"bytes"}],"name":"executeCall","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"role","type":"bytes32"}],"name":"getRoleAdmin","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"role","type":"bytes32"},{"internalType":"address","name":"account","type":"address"}],"name":"grantRole","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"role","type":"bytes32"},{"internalType":"address","name":"account","type":"address"}],"name":"hasRole","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"admin","type":"address"},{"internalType":"address[]","name":"executors","type":"address[]"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"role","type":"bytes32"},{"internalType":"address","name":"account","type":"address"}],"name":"renounceRole","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"role","type":"bytes32"},{"internalType":"address","name":"account","type":"address"}],"name":"revokeRole","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes4","name":"interfaceId","type":"bytes4"}],"name":"supportsInterface","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"}]'
const upgradeExecutorIface = new ethers.utils.Interface(upgradeExecutorAbi)

/**
 * Load and execute all prepared TXs to transfer ownership of Arb and Nova assets.
 * To be used in local env only.
 */
export const executeOwnershipTransfer = async () => {
  const { ethDeployer, arbDeployer, novaDeployer, arbNetwork } = await getDeployersAndConfig();
  const { ethProvider } = await getProviders();

  // fetch protocol owner wallet from local test env
  const { wallet: l1ProtocolOwnerWallet, 
          existingUpgradeExecutor } = (await getProtocolOwnerWallet(arbNetwork, ethProvider));
  const l1ProtocolOwner = l1ProtocolOwnerWallet.connect(
    ethProvider
  );

  if (existingUpgradeExecutor !== undefined) {
    console.log("Existing upgrade executor found, using it to execute txs")
  }

  //// Arb
  const l1ArbProtocolTxs = buildTXs(envVars.l1ArbProtocolTransferTXsLocation);
  console.log("Transfer Arb protocol ownership on L1");
  for (let i = 0; i < l1ArbProtocolTxs.length; i++) {
    console.log("Execute ", l1ArbProtocolTxs[i].data, l1ArbProtocolTxs[i].to);

    if (existingUpgradeExecutor) {
      await (await l1ProtocolOwner.sendTransaction({
        to: existingUpgradeExecutor,
        data: upgradeExecutorIface.encodeFunctionData("executeCall", [l1ArbProtocolTxs[i].to, l1ArbProtocolTxs[i].data])
      })).wait();
    } else {
      await (await l1ProtocolOwner.sendTransaction(l1ArbProtocolTxs[i])).wait();
    }
  }

  const l1ArbTokenBridgeTxs = buildTXs(envVars.l1ArbTokenBridgeTransferTXsLocation);
  console.log("Transfer Arb token bridge ownership on L1");
  for (let i = 0; i < l1ArbTokenBridgeTxs.length; i++) {
    console.log("Execute ", l1ArbTokenBridgeTxs[i].data, l1ArbTokenBridgeTxs[i].to);
    await (await ethDeployer.sendTransaction(l1ArbTokenBridgeTxs[i])).wait();
  }

  const arbTxs = buildTXs(envVars.arbTransferAssetsTXsLocation);
  console.log("Transfer Arb assets ownership on L2");
  for (let i = 0; i < arbTxs.length; i++) {
    if (arbTxs[i].to == ARB_OWNER_PRECOMPILE) {
      // can't simulate arb chain ownership transfer in local network because chain owner is zero address
      continue;
    }
    console.log("Execute ", arbTxs[i].data, arbTxs[i].to);
    await (await arbDeployer.sendTransaction(arbTxs[i])).wait();
  }

  //// Nova
  if (isDeployingToNova()) {
    const l1NovaTokenBridgeTxs = buildTXs(envVars.l1NovaTokenBridgeTransferTXsLocation);
    console.log("Transfer Nova token bridge ownership on L1");
    for (let i = 0; i < l1NovaTokenBridgeTxs.length; i++) {
      console.log("Execute ", l1NovaTokenBridgeTxs[i].data, l1NovaTokenBridgeTxs[i].to);
      await (await ethDeployer.sendTransaction(l1NovaTokenBridgeTxs[i])).wait();
    }

    const novaTxs = buildTXs(envVars.novaTransferAssetsTXsLocation);
    console.log("Transfer Nova assets ownership on L2");
    for (let i = 0; i < novaTxs.length; i++) {
      if (novaTxs[i].to == ARB_OWNER_PRECOMPILE) {
        // can't simulate arb chain ownership transfer in local network because chain owner is zero address
        continue;
      }
      console.log("Execute ", novaTxs[i].data, novaTxs[i].to);
      await (await novaDeployer!.sendTransaction(novaTxs[i])).wait();
    }
  }
};

/**
 * Parse JSON with list of TXs and construct calldata for executing TXs
 *
 * @param fileName
 * @returns
 */
function buildTXs(fileName: string): { data: string; to: string }[] {
  const ownershipTransferTXs: GnosisBatch = JSON.parse(fs.readFileSync(fileName).toString());
  const txs = ownershipTransferTXs["transactions"];

  // construct calldata for every TX
  const txsToExecute = txs.map((tx) => {
    const functionName = tx["contractMethod"]["name"];
    const functionInputs = tx["contractMethod"]["inputs"];
    if (functionInputs.length !== 1) {
      throw new Error("There should be only 1 function input");
    }
    const functionInputValues = Object.values(tx["contractInputsValues"]);
    if (functionInputValues.length !== 1) {
      throw new Error("There should be only 1 function input value");
    }

    const ABI = [
      `function ${functionName}(${functionInputs[0]["type"]} ${functionInputs[0]["name"]})`,
    ];
    const iface = new ethers.utils.Interface(ABI);
    const functionInput = Object.values(functionInputValues)[0];
    return {
      to: tx.to,
      data: iface.encodeFunctionData(functionName, [functionInput]),
    };
  });

  return txsToExecute;
}

/**
 * Fetch protocol owner wallet from local test envirnoment container
 *
 * @param l1ProtocolOwnerAddress
 * @returns
 */
async function getProtocolOwnerWallet(l2Network: L2Network, provider: Provider): Promise<{ wallet: Wallet, existingUpgradeExecutor: string | undefined }> {
  // get protocol owner address
  let l1ProtocolOwnerAddress = await ProxyAdmin__factory.connect(
    await getProxyOwner(l2Network.ethBridge.bridge, provider),
    provider
  ).owner();

  let existingUpgradeExecutor: string | undefined = undefined;
  // assume is upgrade executor if code is not empty
  const isUE = (await provider.getCode(l1ProtocolOwnerAddress)) !== "0x";
  if (isUE) {
    existingUpgradeExecutor = l1ProtocolOwnerAddress;
    const execRole = await (new ethers.Contract(existingUpgradeExecutor, upgradeExecutorAbi, provider)).EXECUTOR_ROLE()
    const logs = await provider.getLogs({
      address: existingUpgradeExecutor,
      topics: [upgradeExecutorIface.getEventTopic("RoleGranted"), execRole],
      fromBlock: 0,
      toBlock: "latest"
    })
    if (logs.length === 0) {
      throw new Error("No executor role granted to upgrade executor")
    }
    // parse last log
    const parsedLog = upgradeExecutorIface.parseLog(logs[logs.length - 1])
    l1ProtocolOwnerAddress = parsedLog.args.account
  }

  let encryptedJsonFile = "/home/user/l1keystore/" + l1ProtocolOwnerAddress + ".key";
  let dockerCommand = "docker exec nitro-testnode_poster_1 cat " + encryptedJsonFile;
  let encryptedJson: string;
  try {
    encryptedJson = execSync(dockerCommand).toString();
  } catch (e) {
    // nitro-testnode_poster_1 -> nitro-testnode-poster-1
    dockerCommand = dockerCommand.split("_").join("-");
    encryptedJson = execSync(dockerCommand).toString();
  }

  return {
    wallet: await Wallet.fromEncryptedJson(encryptedJson, "passphrase"),
    existingUpgradeExecutor
  };
}

/**
 * Print assets and its owners
 */
async function printProxyAdmins() {
  const { arbNetwork, novaNetwork } = await getDeployersAndConfig();
  const { ethProvider, arbProvider, novaProvider } = await getProviders();

  const arbProtocolProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(arbNetwork.ethBridge.bridge, ethProvider),
    ethProvider
  );
  const arbRollupProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(arbNetwork.ethBridge.rollup, ethProvider),
    ethProvider
  );

  console.log("--------– PROTOCOL ----------------");
  console.log("\narb rollup", arbNetwork.ethBridge.rollup);
  console.log("arb rollup's proxy admin", arbRollupProxyAdmin.address);

  console.log("\narb protocol proxyAdmin", arbProtocolProxyAdmin.address);
  console.log("arb protocol proxyAdmin's owner", await arbProtocolProxyAdmin.owner());

  if (isDeployingToNova()) {
    const novaProtocolProxyAdmin = ProxyAdmin__factory.connect(
      await getProxyOwner(novaNetwork!.ethBridge.bridge, ethProvider),
      ethProvider
    );
    const novaRollupProxyAdmin = ProxyAdmin__factory.connect(
      await getProxyOwner(novaNetwork!.ethBridge.rollup, ethProvider),
      ethProvider
    );

    console.log("\nnova rollup", novaNetwork!.ethBridge.rollup);
    console.log("nova rollup's proxy admin", novaRollupProxyAdmin.address);

    console.log("\nnova protocol proxyAdmin", novaProtocolProxyAdmin.address);
    console.log("nova protocol proxyAdmin's owner", await novaProtocolProxyAdmin.owner());
  }

  console.log("\n--------– TOKEN BRIDGE ----------------");
  console.log("\narb l1ProxyAdmin", arbNetwork.tokenBridge.l1ProxyAdmin);
  console.log(
    "arb l1ProxyAdmin's owner",
    await ProxyAdmin__factory.connect(arbNetwork.tokenBridge.l1ProxyAdmin, ethProvider).owner()
  );

  console.log("\narb l2ProxyAdmin", arbNetwork.tokenBridge.l2ProxyAdmin);
  console.log(
    "arb l2ProxyAdmin's owner",
    await ProxyAdmin__factory.connect(arbNetwork.tokenBridge.l2ProxyAdmin, arbProvider).owner()
  );

  console.log("\narb l1GatewayRouter", arbNetwork.tokenBridge.l1GatewayRouter);
  console.log(
    "arb l1GatewayRouter's owner",
    await L1GatewayRouter__factory.connect(
      arbNetwork.tokenBridge.l1GatewayRouter,
      ethProvider
    ).owner()
  );

  console.log("\narb l1CustomGateway", arbNetwork.tokenBridge.l1CustomGateway);
  console.log(
    "arb l1CustomGateway's owner",
    await L1CustomGateway__factory.connect(
      arbNetwork.tokenBridge.l1CustomGateway,
      ethProvider
    ).owner()
  );

  if (isDeployingToNova()) {
    console.log("\nnova l1ProxyAdmin", novaNetwork!.tokenBridge.l1ProxyAdmin);
    console.log(
      "nova l1ProxyAdmin's owner",
      await ProxyAdmin__factory.connect(novaNetwork!.tokenBridge.l1ProxyAdmin, ethProvider).owner()
    );

    console.log("\nnova l2ProxyAdmin", novaNetwork!.tokenBridge.l2ProxyAdmin);
    console.log(
      "nova l2ProxyAdmin's owner",
      await ProxyAdmin__factory.connect(
        novaNetwork!.tokenBridge.l2ProxyAdmin,
        novaProvider!
      ).owner()
    );

    console.log("\nnova l1GatewayRouter", novaNetwork!.tokenBridge.l1GatewayRouter);
    console.log(
      "nova l1GatewayRouter's owner",
      await L1GatewayRouter__factory.connect(
        novaNetwork!.tokenBridge.l1GatewayRouter,
        ethProvider
      ).owner()
    );

    console.log("\nnova l1CustomGateway", novaNetwork!.tokenBridge.l1CustomGateway);
    console.log(
      "nova l1CustomGateway's owner",
      await L1CustomGateway__factory.connect(
        novaNetwork!.tokenBridge.l1CustomGateway,
        ethProvider
      ).owner()
    );
  }
}

async function main() {
  if (!isLocalDeployment()) {
    console.log("This is a test script for local network testing");
    return;
  }

  await printProxyAdmins();
  await executeOwnershipTransfer();
}

main().then(() => console.log("Done."));
