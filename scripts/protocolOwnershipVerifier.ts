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

/**
 * Verifies ownership of protocol contracts is successfully transferred to DAO
 */
export const verifyOwnership = async () => {
  const { arbNetwork, novaNetwork } = await getDeployersAndConfig();
  const { ethProvider, arbProvider, novaProvider } = await getProviders();

  const contractAddresses = require("../" + DEPLOYED_CONTRACTS_FILE_NAME);
  const l1Executor = contractAddresses["l1Executor"];
  const l2Executor = contractAddresses["l2Executor"];
  const novaExecutor = contractAddresses["novaUpgradeExecutorProxy"];

  console.log("Verify ownership over Arb protocol contracts");
  const arbOneRollup = RollupCore__factory.connect(arbNetwork.ethBridge.rollup, ethProvider);
  await verifyProtocolOwnership(arbOneRollup, l1Executor, ethProvider);

  console.log("Verify ownership over Arb token bridge contracts");
  await verifyTokenBridgeOwnership(arbNetwork, l1Executor, l2Executor, ethProvider, arbProvider);

  console.log("Verify ownership over Nova protocol contracts");
  const novaRollup = RollupCore__factory.connect(novaNetwork.ethBridge.rollup, ethProvider);
  await verifyProtocolOwnership(novaRollup, l1Executor, ethProvider);

  console.log("Verify ownership over Nova token bridge contracts");
  await verifyTokenBridgeOwnership(
    novaNetwork,
    l1Executor,
    novaExecutor,
    ethProvider,
    novaProvider
  );
};

/**
 * Verify:
 * - bridge, inbox, seqInbox, outbox and challengeManager are owned by proxyAdmin
 * - proxyAdmin and rollup are owned by DAO (ownership transferred from multisig)
 */
async function verifyProtocolOwnership(
  rollupCore: RollupCore,
  l1Executor: string,
  ethProvider: Provider
) {
  const contracts = await getProtocolContracts(rollupCore, ethProvider);

  //// verify ownership over rollup and proxyAdmin is transferred to DAO

  const bridgeProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(contracts["bridge"].address, ethProvider),
    ethProvider
  );
  assertEquals(
    await bridgeProxyAdmin.owner(),
    l1Executor,
    "l1Executor should be bridge's proxyAdmin's owner"
  );

  const inboxProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(contracts["inbox"].address, ethProvider),
    ethProvider
  );
  assertEquals(
    await inboxProxyAdmin.owner(),
    l1Executor,
    "l1Executor should be inbox's proxyAdmin's owner"
  );

  const sequencerInboxProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(contracts["sequencerInbox"].address, ethProvider),
    ethProvider
  );
  assertEquals(
    await sequencerInboxProxyAdmin.owner(),
    l1Executor,
    "l1Executor should be sequencerInbox's proxyAdmin's owner"
  );

  const outboxProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(contracts["outbox"].address, ethProvider),
    ethProvider
  );
  assertEquals(
    await outboxProxyAdmin.owner(),
    l1Executor,
    "l1Executor should be outbox's proxyAdmin's owner"
  );

  const challengeManagerProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(contracts["challengeManager"].address, ethProvider),
    ethProvider
  );
  assertEquals(
    await challengeManagerProxyAdmin.owner(),
    l1Executor,
    "l1Executor should be challengeManager's proxyAdmin's owner"
  );

  // Rollups proxy admin should be executor directly
  assertEquals(
    await getProxyOwner(contracts["rollup"].address, ethProvider),
    l1Executor,
    "l1Executor should be rollups's proxyAdmin's owner"
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
  //// check owner of L1 token bridge's proxyAdmins is L1 executor

  const l1RouterProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(l2Network.tokenBridge.l1GatewayRouter, ethProvider),
    ethProvider
  );
  assertEquals(
    await l1RouterProxyAdmin.owner(),
    l1Executor,
    "l1Executor should be l1RouterProxyAdmin's proxyAdmin's owner"
  );

  const l1ERC20GatewayProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(l2Network.tokenBridge.l1ERC20Gateway, ethProvider),
    ethProvider
  );
  assertEquals(
    await l1ERC20GatewayProxyAdmin.owner(),
    l1Executor,
    "l1Executor should be l1ERC20Gateway's proxyAdmin's owner"
  );

  const l1CustomGatewayProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(l2Network.tokenBridge.l1CustomGateway, ethProvider),
    ethProvider
  );
  assertEquals(
    await l1CustomGatewayProxyAdmin.owner(),
    l1Executor,
    "l1Executor should be l1CustomGateway's proxyAdmin's owner"
  );

  const l1WethGatewayProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(l2Network.tokenBridge.l1WethGateway, ethProvider),
    ethProvider
  );
  assertEquals(
    await l1WethGatewayProxyAdmin.owner(),
    l1Executor,
    "l1Executor should be l1WethGateway's proxyAdmin's owner"
  );

  //// check owner of L1 token bridge's proxyAdmins is L1 executor

  const l2GatewayRouterProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(l2Network.tokenBridge.l2GatewayRouter, l2Provider),
    l2Provider
  );
  assertEquals(
    await l2GatewayRouterProxyAdmin.owner(),
    l2Executor,
    "l2Executor should be l2GatewayRouter's proxyAdmin's owner"
  );

  const l2ERC20GatewayProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(l2Network.tokenBridge.l2ERC20Gateway, l2Provider),
    l2Provider
  );
  assertEquals(
    await l2ERC20GatewayProxyAdmin.owner(),
    l2Executor,
    "l2Executor should be l2ERC20Gateway's proxyAdmin's owner"
  );

  const l2CustomGatewayProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(l2Network.tokenBridge.l2CustomGateway, l2Provider),
    l2Provider
  );
  assertEquals(
    await l2CustomGatewayProxyAdmin.owner(),
    l2Executor,
    "l2Executor should be l2CustomGateway's proxyAdmin's owner"
  );

  const l2WethGatewayProxyAdmin = ProxyAdmin__factory.connect(
    await getProxyOwner(l2Network.tokenBridge.l2WethGateway, l2Provider),
    l2Provider
  );
  assertEquals(
    await l2WethGatewayProxyAdmin.owner(),
    l2Executor,
    "l2Executor should be l2WethGateway's proxyAdmin's owner"
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
