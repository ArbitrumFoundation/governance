import { getDeployersAndConfig, getProviders } from "./providerSetup";
import { Wallet } from "ethers";
import fs from "fs";
import { getProxyOwner } from "./testUtils";
import { ProxyAdmin__factory } from "../typechain-types";
import { execSync } from "child_process";

const ARB_TXS_FILE_NAME = "files/arbTransferAssetsTXs.json";
const NOVA_TXS_FILE_NAME = "files/novaTransferAssetsTXs.json";

/**
 * Load and execute all prepared TXs to transfer ownership of Arb and Nova assets.
 * To be used in local env only.
 */
export const executeOwnershipTransfer = async () => {
  const { ethDeployer, arbDeployer, novaDeployer, arbNetwork } = await getDeployersAndConfig();
  const { ethProvider } = await getProviders();

  // fetch protocol owner wallet from local test env
  const l1ProtocolOwnerAddress = await ProxyAdmin__factory.connect(
    await getProxyOwner(arbNetwork.ethBridge.bridge, ethProvider),
    ethProvider
  ).owner();
  const l1ProtocolOwner = (await getProtocolOwnerWallet(l1ProtocolOwnerAddress)).connect(
    ethProvider
  );

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
 * Fetch protocol owner wallet from local test envirnoment container
 *
 * @param l1ProtocolOwnerAddress
 * @returns
 */
async function getProtocolOwnerWallet(l1ProtocolOwnerAddress: string): Promise<Wallet> {
  // to lower case and remove '0x' prefix
  const address = l1ProtocolOwnerAddress.substring(2).toLocaleLowerCase();

  // find file and get contents
  const encryptedJsonFile = execSync(
    "docker exec nitro-poster-1 sudo find /home/user/l1keystore -maxdepth 1 -name '*" +
      address +
      "*' -print"
  ).toString();

  if (encryptedJsonFile.length == 0) {
    throw new Error("Could not locate wallet data for address " + address);
  }

  const encryptedJson = execSync(
    "docker exec nitro-poster-1 sudo cat " + encryptedJsonFile
  ).toString();

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
