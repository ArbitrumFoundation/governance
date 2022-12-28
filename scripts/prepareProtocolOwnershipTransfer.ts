import { envVars, getDeployersAndConfig, getProviders } from "./providerSetup";
import { getProxyOwner } from "./testUtils";
import { ProxyAdmin__factory } from "../typechain-types";
import { RollupAdminLogic__factory } from "@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory";
import { ethers, PopulatedTransaction } from "ethers";
import fs from "fs";
import { L2Network } from "@arbitrum/sdk";

const ARB_TXS_FILE_NAME = "files/arbTransferAssetsTXs.json";
const NOVA_TXS_FILE_NAME = "files/novaTransferAssetsTXs.json";

/**
 * Generate calldata for all the TXs needed to transfer asset ownership to DAO.
 * Output with TX data is written to JSON files for Arb and Nova.
 *
 */
export const prepareAssetTransferTXs = async () => {
  const { arbNetwork, novaNetwork } = await getDeployersAndConfig();
  const { ethProvider, arbProvider, novaProvider } = await getProviders();

  const contractAddresses = require("../" + envVars.deployedContractsLocation);
  const l1Executor = contractAddresses["l1Executor"];
  const arbExecutor = contractAddresses["l2Executor"];
  const novaExecutor = contractAddresses["novaUpgradeExecutorProxy"];

  // TXs to transfer ownership of ArbOne assets
  const arbTXs = await generateAssetTransferTXs(
    arbNetwork,
    ethProvider,
    arbProvider,
    l1Executor,
    arbExecutor
  );
  fs.writeFileSync(ARB_TXS_FILE_NAME, JSON.stringify(arbTXs));
  console.log("Arb TXs file:", ARB_TXS_FILE_NAME);

  // TXs to transfer ownership of Nova assets
  const novaTXs = await generateAssetTransferTXs(
    novaNetwork,
    ethProvider,
    novaProvider,
    l1Executor,
    novaExecutor
  );
  fs.writeFileSync(NOVA_TXS_FILE_NAME, JSON.stringify(novaTXs));
  console.log("Nova TXs file:", NOVA_TXS_FILE_NAME);
};

/**
 * Generate data for 4 ownership transfer TXs:
 * - rollup
 * - protocol L1 proxy admin
 * - token bridge L1 proxy admin
 * - token bridge L2 proxy admin
 *
 * @returns
 */
async function generateAssetTransferTXs(
  l2Network: L2Network,
  l1Provider: ethers.providers.Provider,
  l2Provider: ethers.providers.Provider,
  l1Executor: string,
  l2Executor: string
) {
  const l1RollupOwnerTX = await getRollupOwnerTransferTX(l2Network, l1Provider, l1Executor);
  // protocol L1 proxy admin
  const l1ProtocolProxyAdminOwnerTX = await getProxyAdminOwnerTransferTX(
    await getProxyOwner(l2Network.ethBridge.inbox, l1Provider),
    l1Provider,
    l1Executor
  );
  // L1 token bridge proxy admin
  const l1TokenBridgeProxyAdminOwnerTX = await getProxyAdminOwnerTransferTX(
    await getProxyOwner(l2Network.tokenBridge.l1GatewayRouter, l1Provider),
    l1Provider,
    l1Executor
  );
  // L2 token bridge proxy admin
  const l2TokenBridgeProxyAdminOwnerTX = await getProxyAdminOwnerTransferTX(
    await getProxyOwner(l2Network.tokenBridge.l2GatewayRouter, l2Provider),
    l2Provider,
    l2Executor
  );
  return {
    l1RollupOwnerTX: l1RollupOwnerTX,
    l1ProtocolProxyAdminOwnerTX: l1ProtocolProxyAdminOwnerTX,
    l1TokenBridgeProxyAdminOwnerTX: l1TokenBridgeProxyAdminOwnerTX,
    l2TokenBridgeProxyAdminOwnerTX: l2TokenBridgeProxyAdminOwnerTX,
  };
}

/**
 * Set rollup's owner
 */
async function getRollupOwnerTransferTX(
  l2Network: L2Network,
  ethProvider: ethers.providers.Provider,
  l1Executor: string
): Promise<PopulatedTransaction> {
  const rollup = RollupAdminLogic__factory.connect(l2Network.ethBridge.rollup, ethProvider);
  const setRollupOwnerTX = await rollup.populateTransaction.setOwner(l1Executor);

  return setRollupOwnerTX;
}

/**
 * Set proxy admin's owner
 */
async function getProxyAdminOwnerTransferTX(
  proxyAdminAddress: string,
  provider: ethers.providers.Provider,
  executorAddress: string
): Promise<PopulatedTransaction> {
  const proxyAdmin = ProxyAdmin__factory.connect(proxyAdminAddress, provider);
  const proxyAdminOwnerTX = await proxyAdmin.populateTransaction.transferOwnership(executorAddress);

  return proxyAdminOwnerTX;
}

async function main() {
  await prepareAssetTransferTXs();
}

main().then(() => console.log("Done."));
