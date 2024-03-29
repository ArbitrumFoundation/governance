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

/**
 * Load and execute all prepared TXs to transfer ownership of Arb and Nova assets.
 * To be used in local env only.
 */
export const executeOwnershipTransfer = async () => {
  const { ethDeployer, arbDeployer, novaDeployer, arbNetwork } = await getDeployersAndConfig();
  const { ethProvider } = await getProviders();

  // fetch protocol owner wallet from local test env
  const l1ProtocolOwner = (await getProtocolOwnerWallet(arbNetwork, ethProvider)).connect(
    ethProvider
  );

  //// Arb
  const l1ArbProtocolTxs = buildTXs(envVars.l1ArbProtocolTransferTXsLocation);
  console.log("Transfer Arb protocol ownership on L1");
  for (let i = 0; i < l1ArbProtocolTxs.length; i++) {
    console.log("Execute ", l1ArbProtocolTxs[i].data, l1ArbProtocolTxs[i].to);
    await (await l1ProtocolOwner.sendTransaction(l1ArbProtocolTxs[i])).wait();
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
async function getProtocolOwnerWallet(l2Network: L2Network, provider: Provider): Promise<Wallet> {
  // get protocol owner address
  const l1ProtocolOwnerAddress = await ProxyAdmin__factory.connect(
    await getProxyOwner(l2Network.ethBridge.bridge, provider),
    provider
  ).owner();

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

  return await Wallet.fromEncryptedJson(encryptedJson, "passphrase");
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
