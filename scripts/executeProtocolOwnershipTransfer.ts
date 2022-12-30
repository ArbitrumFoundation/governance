import { envVars, getDeployersAndConfig, getProviders } from "./providerSetup";
import { Wallet } from "ethers";
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

/**
 * Load and execute all prepared TXs to transfer ownership of Arb and Nova assets.
 * To be used in local env only.
 */
export const executeOwnershipTransfer = async () => {
  const { ethDeployer, arbDeployer, novaDeployer, arbNetwork, novaNetwork } =
    await getDeployersAndConfig();
  const { ethProvider, arbProvider, novaProvider } = await getProviders();

  // fetch protocol owner wallet from local test env
  const l1ProtocolOwner = (await getProtocolOwnerWallet(arbNetwork, ethProvider)).connect(
    ethProvider
  );

  // get executor addresses
  const contractAddresses = require("../" + envVars.deployedContractsLocation);
  const l1Executor = contractAddresses["l1Executor"];
  const arbExecutor = contractAddresses["l2Executor"];
  const novaExecutor = contractAddresses["novaUpgradeExecutorProxy"];

  //// Arb transfer
  console.log("Transfer Arb asset's ownership");
  const arbTxs = fetchAssetTransferTXs(envVars.arbTransferAssetsTXsLocation);

  if ((await getOwner(arbNetwork.ethBridge.rollup, arbNetwork, ethProvider)) != l1Executor) {
    console.log("Set new Arb rollup owner");
    await (await l1ProtocolOwner.sendTransaction(arbTxs["l1RollupOwnerTX"])).wait();
  }
  if ((await getOwner(arbNetwork.ethBridge.bridge, arbNetwork, ethProvider)) != l1Executor) {
    console.log("Set new Arb protocol proxy admin owner");
    await (await l1ProtocolOwner.sendTransaction(arbTxs["l1ProtocolProxyAdminOwnerTX"])).wait();
  }
  if (
    (await getOwner(arbNetwork.tokenBridge.l1GatewayRouter, arbNetwork, ethProvider)) != l1Executor
  ) {
    console.log("Set new Arb L1 token bridge's proxy admin's owner");
    await (await ethDeployer.sendTransaction(arbTxs["l1TokenBridgeProxyAdminOwnerTX"])).wait();
  }
  if (
    (await getOwner(arbNetwork.tokenBridge.l2GatewayRouter, arbNetwork, arbProvider)) != arbExecutor
  ) {
    console.log("Set new Arb L2 token bridge proxy admin owner");
    await (await arbDeployer.sendTransaction(arbTxs["l2TokenBridgeProxyAdminOwnerTX"])).wait();
  }
  if (
    (await L1GatewayRouter__factory.connect(
      arbNetwork.tokenBridge.l1GatewayRouter,
      ethProvider
    ).owner()) != l1Executor
  ) {
    console.log("Set new Arb L1 gateway router owner");
    await (await ethDeployer.sendTransaction(arbTxs["l1GatewayRouterOwnerTX"])).wait();
  }
  if (
    (await L1CustomGateway__factory.connect(
      arbNetwork.tokenBridge.l1CustomGateway,
      ethProvider
    ).owner()) != l1Executor
  ) {
    console.log("Set new Arb L1 custom gateway owner");
    await (await ethDeployer.sendTransaction(arbTxs["l1CustomGatewayOwnerTX"])).wait();
  }

  //// Nova
  console.log("Transfer Nova asset's ownership");
  const novaTxs = fetchAssetTransferTXs(envVars.novaTransferAssetsTXsLocation);

  if ((await getOwner(novaNetwork.ethBridge.rollup, novaNetwork, ethProvider)) != l1Executor) {
    console.log("Set new Nova rollup owner");
    await (await l1ProtocolOwner.sendTransaction(novaTxs["l1RollupOwnerTX"])).wait();
  }
  if ((await getOwner(novaNetwork.ethBridge.bridge, novaNetwork, ethProvider)) != l1Executor) {
    console.log("Set new Nova protocol proxy admin owner");
    await (await l1ProtocolOwner.sendTransaction(novaTxs["l1ProtocolProxyAdminOwnerTX"])).wait();
  }
  if (
    (await getOwner(novaNetwork.tokenBridge.l1GatewayRouter, novaNetwork, ethProvider)) !=
    l1Executor
  ) {
    console.log("Set new Nova L1 token bridge proxy admin owner");
    await (await ethDeployer.sendTransaction(novaTxs["l1TokenBridgeProxyAdminOwnerTX"])).wait();
  }
  if (
    (await getOwner(novaNetwork.tokenBridge.l2GatewayRouter, novaNetwork, novaProvider)) !=
    novaExecutor
  ) {
    console.log("Set new Nova L2 token bridge proxy admin owner");
    await (await novaDeployer.sendTransaction(novaTxs["l2TokenBridgeProxyAdminOwnerTX"])).wait();
  }
  if (
    (await L1GatewayRouter__factory.connect(
      novaNetwork.tokenBridge.l1GatewayRouter,
      ethProvider
    ).owner()) != l1Executor
  ) {
    console.log("Set new Nova L1 gateway router owner");
    await (await ethDeployer.sendTransaction(novaTxs["l1GatewayRouterOwnerTX"])).wait();
  }
  if (
    (await L1CustomGateway__factory.connect(
      novaNetwork.tokenBridge.l1CustomGateway,
      ethProvider
    ).owner()) != l1Executor
  ) {
    console.log("Set new Nova L1 custom gateway owner");
    await (await ethDeployer.sendTransaction(novaTxs["l1CustomGatewayOwnerTX"])).wait();
  }
};

async function getOwner(
  contractAddress: string,
  l2Network: L2Network,
  provider: Provider
): Promise<string> {
  if (contractAddress == l2Network.ethBridge.rollup) {
    return await getProxyOwner(l2Network.ethBridge.rollup, provider);
  }

  const proxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(contractAddress, provider),
    provider
  );

  return await proxyAdmin.owner();
}

/**
 * Load prepared TXs from JSON file
 * @param fileName
 * @returns
 */
export const fetchAssetTransferTXs = (fileName: string) => {
  let ownershipTransferTXs: { [key: string]: { data: string; to: string } } = JSON.parse(
    fs.readFileSync(fileName).toString()
  );

  return ownershipTransferTXs;
};

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
  let dockerCommand = "docker exec nitro_poster_1 cat " + encryptedJsonFile;
  let encryptedJson: string;
  try {
    encryptedJson = execSync(dockerCommand).toString();
  } catch (e) {
    // nitro_poster_1 -> nitro-poster-1
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

  const novaProtocolProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(novaNetwork.ethBridge.bridge, ethProvider),
    ethProvider
  );
  const novaRollupProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(novaNetwork.ethBridge.rollup, ethProvider),
    ethProvider
  );

  console.log("--------– PROTOCOL ----------------");
  console.log("\narb rollup", arbNetwork.ethBridge.rollup);
  console.log("arb rollup's proxy admin", arbRollupProxyAdmin.address);

  console.log("\narb protocol proxyAdmin", arbProtocolProxyAdmin.address);
  console.log("arb protocol proxyAdmin's owner", await arbProtocolProxyAdmin.owner());

  console.log("\nnova rollup", novaNetwork.ethBridge.rollup);
  console.log("nova rollup's proxy admin", novaRollupProxyAdmin.address);

  console.log("\nnova protocol proxyAdmin", novaProtocolProxyAdmin.address);
  console.log("nova protocol proxyAdmin's owner", await novaProtocolProxyAdmin.owner());

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

  console.log("\nnova l1ProxyAdmin", novaNetwork.tokenBridge.l1ProxyAdmin);
  console.log(
    "nova l1ProxyAdmin's owner",
    await ProxyAdmin__factory.connect(novaNetwork.tokenBridge.l1ProxyAdmin, ethProvider).owner()
  );

  console.log("\nnova l2ProxyAdmin", novaNetwork.tokenBridge.l2ProxyAdmin);
  console.log(
    "nova l2ProxyAdmin's owner",
    await ProxyAdmin__factory.connect(novaNetwork.tokenBridge.l2ProxyAdmin, novaProvider).owner()
  );

  console.log("\nova l1GatewayRouter", novaNetwork.tokenBridge.l1GatewayRouter);
  console.log(
    "nova l1GatewayRouter's owner",
    await L1GatewayRouter__factory.connect(
      novaNetwork.tokenBridge.l1GatewayRouter,
      ethProvider
    ).owner()
  );

  console.log("\nova l1CustomGateway", novaNetwork.tokenBridge.l1CustomGateway);
  console.log(
    "nova l1CustomGateway's owner",
    await L1CustomGateway__factory.connect(
      novaNetwork.tokenBridge.l1CustomGateway,
      ethProvider
    ).owner()
  );
}

async function main() {
  await printProxyAdmins();
  await executeOwnershipTransfer();
}

main().then(() => console.log("Done."));
