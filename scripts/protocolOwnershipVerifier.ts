import { RollupCore__factory } from "@arbitrum/sdk/dist/lib/abi/factories/RollupCore__factory";
import { Bridge__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Bridge__factory";
import { Inbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Inbox__factory";
import { SequencerInbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/SequencerInbox__factory";
import { Outbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Outbox__factory";
import { ChallengeManager__factory } from "@arbitrum/sdk/dist/lib/abi/factories/ChallengeManager__factory";

import { getDeployersAndConfig, getProviders } from "./providerSetup";
import { assertEquals, getProxyOwner } from "./testUtils";
import { ProxyAdmin__factory } from "../typechain-types";
import { Provider } from "@ethersproject/providers";
import { RollupCore } from "@arbitrum/sdk/dist/lib/abi/RollupCore";
import { L2Network } from "@arbitrum/sdk";

const DEPLOYED_CONTRACTS_FILE_NAME = "deployedContracts.json";

const L1_ARB_PROTOCOL_PROXY_ADMIN = "0x554723262467f125ac9e1cdfa9ce15cc53822dbd";
const L1_NOVA_PROTOCOL_PROXY_ADMIN = "0x71D78dC7cCC0e037e12de1E50f5470903ce37148";

/**
 * Verifies ownership of protocol contracts is successfully transferred to DAO
 */
export const verifyOwnership = async () => {
  const { arbNetwork, novaNetwork } = await getDeployersAndConfig();
  const { ethProvider, arbProvider, novaProvider } = await getProviders();

  const contractAddresses = require("../" + DEPLOYED_CONTRACTS_FILE_NAME);
  const l1Executor = contractAddresses["l1Executor"];
  const l2Executor = contractAddresses["l2Executor"];

  console.log("Verify ownership over Arb protocol contracts");
  const arbOneRollup = RollupCore__factory.connect(arbNetwork.ethBridge.rollup, ethProvider);
  await verifyProtocolOwnership(arbOneRollup, L1_ARB_PROTOCOL_PROXY_ADMIN, l1Executor, ethProvider);

  console.log("Verify ownership over Arb token bridge contracts");
  await verifyTokenBridgeOwnership(arbNetwork, l1Executor, l2Executor, ethProvider, arbProvider);

  console.log("Verify ownership over Nova protocol contracts");
  const novaRollup = RollupCore__factory.connect(novaNetwork.ethBridge.rollup, ethProvider);
  await verifyProtocolOwnership(novaRollup, L1_NOVA_PROTOCOL_PROXY_ADMIN, l1Executor, ethProvider);

  console.log("Verify ownership over Nova token bridge contracts");
  await verifyTokenBridgeOwnership(novaNetwork, l1Executor, l2Executor, ethProvider, novaProvider);
};

/**
 * Verify:
 * - bridge, inbox, seqInbox, outbox and challengeManager are owned by proxyAdmin
 * - proxyAdmin and rollup are owned by DAO (ownership transferred from multisig)
 */
async function verifyProtocolOwnership(
  rollupCore: RollupCore,
  proxyAdmin: string,
  l1Executor: string,
  ethProvider: Provider
) {
  const contracts = await getProtocolContracts(rollupCore, ethProvider);

  //// verify proxy admin

  assertEquals(
    await getProxyOwner(contracts["bridge"].address, ethProvider),
    proxyAdmin,
    proxyAdmin + " should be bridge's proxy admin"
  );
  assertEquals(
    await getProxyOwner(contracts["inbox"].address, ethProvider),
    proxyAdmin,
    proxyAdmin + " should be inbox's proxy admin"
  );
  assertEquals(
    await getProxyOwner(contracts["sequencerInbox"].address, ethProvider),
    proxyAdmin,
    proxyAdmin + " should be sequencerInbox's proxy admin"
  );
  assertEquals(
    await getProxyOwner(contracts["outbox"].address, ethProvider),
    proxyAdmin,
    proxyAdmin + " should be outbox's proxy admin"
  );
  assertEquals(
    await getProxyOwner(contracts["challengeManager"].address, ethProvider),
    proxyAdmin,
    proxyAdmin + " should be challengeManager's proxy admin"
  );

  //// verify ownership over rollup and proxyAdmin is transferred to DAO

  assertEquals(
    await getProxyOwner(contracts["rollup"].address, ethProvider),
    l1Executor,
    "l1Executor should be rollups's owner"
  );
  const proxyAdminContract = ProxyAdmin__factory.connect(proxyAdmin, ethProvider);
  assertEquals(
    await proxyAdminContract.owner(),
    l1Executor,
    "l1Executor should be ethBridge proxyAdmin's owner"
  );
}

/**
 * Verify:
 * - L1/L2 router, erc20 gateway, custom gateway and weth gateway are owned by proxyAdmin
 * - proxyAdmin is owned by DAO (ownership transferred from multisig)
 */
async function verifyTokenBridgeOwnership(
  l2Network: L2Network,
  l1Executor: string,
  l2Executor: string,
  ethProvider: Provider,
  l2Provider: Provider
) {
  //// check l1ProxyAdmin is proxy admin of token bridge contracts

  const l1ProxyAdmin = l2Network.tokenBridge.l1ProxyAdmin;
  assertEquals(
    await getProxyOwner(l2Network.tokenBridge.l1GatewayRouter, ethProvider),
    l1ProxyAdmin,
    l1ProxyAdmin + " should be l1GatewayRouter's proxy admin"
  );
  assertEquals(
    await getProxyOwner(l2Network.tokenBridge.l1ERC20Gateway, ethProvider),
    l1ProxyAdmin,
    l1ProxyAdmin + " should be l1ERC20Gateway's proxy admin"
  );
  assertEquals(
    await getProxyOwner(l2Network.tokenBridge.l1CustomGateway, ethProvider),
    l1ProxyAdmin,
    l1ProxyAdmin + " should be l1CustomGateway's proxy admin"
  );
  assertEquals(
    await getProxyOwner(l2Network.tokenBridge.l1WethGateway, ethProvider),
    l1ProxyAdmin,
    l1ProxyAdmin + " should be l1WethGateway's proxy admin"
  );

  //// check l2ProxyAdmin is proxy admin of token bridge contracts

  const l2ProxyAdmin = l2Network.tokenBridge.l2ProxyAdmin;
  assertEquals(
    await getProxyOwner(l2Network.tokenBridge.l2GatewayRouter, l2Provider),
    l2ProxyAdmin,
    l2ProxyAdmin + " should be l2GatewayRouter's proxy admin"
  );
  assertEquals(
    await getProxyOwner(l2Network.tokenBridge.l2ERC20Gateway, l2Provider),
    l2ProxyAdmin,
    l2ProxyAdmin + " should be l2ERC20Gateway's proxy admin"
  );
  assertEquals(
    await getProxyOwner(l2Network.tokenBridge.l2CustomGateway, l2Provider),
    l2ProxyAdmin,
    l2ProxyAdmin + " should be l2CustomGateway's proxy admin"
  );
  assertEquals(
    await getProxyOwner(l2Network.tokenBridge.l2WethGateway, l2Provider),
    l2ProxyAdmin,
    l2ProxyAdmin + " should be l2WethGateway's proxy admin"
  );

  //// verify ownership over rollup and proxyAdmin is transferred to DAO

  const l1ProxyAdminContract = ProxyAdmin__factory.connect(l1ProxyAdmin, ethProvider);
  assertEquals(
    await l1ProxyAdminContract.owner(),
    l1Executor,
    "l1Executor should be tokenBridge proxyAdmin's owner"
  );

  const l2ProxyAdminContract = ProxyAdmin__factory.connect(l2ProxyAdmin, l2Provider);
  assertEquals(
    await l2ProxyAdminContract.owner(),
    l2Executor,
    "l2Executor should be tokenBridge proxyAdmin's owner"
  );
}

/**
 * Get protocol contracts by querying the rollup cotract.
 */
async function getProtocolContracts(rollupCore: RollupCore, provider: Provider) {
  return {
    rollup: rollupCore,
    bridge: Bridge__factory.connect(await rollupCore.bridge(), provider),
    inbox: Inbox__factory.connect(await rollupCore.inbox(), provider),
    sequencerInbox: SequencerInbox__factory.connect(await rollupCore.sequencerInbox(), provider),
    outbox: Outbox__factory.connect(await rollupCore.outbox(), provider),
    challengeManager: ChallengeManager__factory.connect(
      await rollupCore.challengeManager(),
      provider
    ),
  };
}

async function main() {
  console.log("Start verification process...");
  await verifyOwnership();
}

main().then(() => console.log("Done."));
