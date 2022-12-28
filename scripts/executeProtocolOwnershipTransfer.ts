import { getDeployerAddresses, getDeployersAndConfig, getProviders } from "./providerSetup";
import { Wallet } from "ethers";
import fs from "fs";
import { getProxyOwner } from "./testUtils";
import { ProxyAdmin__factory } from "../typechain-types";

const ARB_TXS_FILE_NAME = "files/arbTransferAssetsTXs.json";
const NOVA_TXS_FILE_NAME = "files/novaTransferAssetsTXs.json";

/**
 * Load and execute all prepared TXs to transfer ownership of Arb and Nova assets.
 * To be used in local env only.
 */
export const executeOwnershipTransfer = async () => {
  const { ethDeployer, arbDeployer, novaDeployer } = await getDeployersAndConfig();
  const { ethProvider } = await getProviders();

  const l1ProtocolOwner = (
    await Wallet.fromEncryptedJson(fs.readFileSync("./scripts/params").toString(), "passphrase")
  ).connect(ethProvider);

  //// Arb
  console.log("Transfer Arb asset's ownership");
  const arbTxs = fetchAssetTransferTXs(ARB_TXS_FILE_NAME);
  await (await l1ProtocolOwner.sendTransaction(arbTxs["l1RollupOwnerTX"])).wait();
  await (await l1ProtocolOwner.sendTransaction(arbTxs["l1ProtocolProxyAdminOwnerTX"])).wait();
  await (await ethDeployer.sendTransaction(arbTxs["l1TokenBridgeProxyAdminOwnerTX"])).wait();
  await (await arbDeployer.sendTransaction(arbTxs["l2TokenBridgeProxyAdminOwnerTX"])).wait();

  //// Nova
  console.log("Transfer Nova asset's ownership");
  const novaTxs = fetchAssetTransferTXs(NOVA_TXS_FILE_NAME);
  await (await l1ProtocolOwner.sendTransaction(novaTxs["l1RollupOwnerTX"])).wait();
  await (await l1ProtocolOwner.sendTransaction(novaTxs["l1ProtocolProxyAdminOwnerTX"])).wait();
  await (await ethDeployer.sendTransaction(novaTxs["l1TokenBridgeProxyAdminOwnerTX"])).wait();
  await (await novaDeployer.sendTransaction(novaTxs["l2TokenBridgeProxyAdminOwnerTX"])).wait();
};

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
}

async function main() {
  await printProxyAdmins();
  await executeOwnershipTransfer();
}

main().then(() => console.log("Done."));
