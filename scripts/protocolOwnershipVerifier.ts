import { RollupCore__factory } from "@arbitrum/sdk/dist/lib/abi/factories/RollupCore__factory";
import { Bridge__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Bridge__factory";
import { Inbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Inbox__factory";
import { SequencerInbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/SequencerInbox__factory";
import { Outbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Outbox__factory";
import { ChallengeManager__factory } from "@arbitrum/sdk/dist/lib/abi/factories/ChallengeManager__factory";
import { ArbOwner__factory } from "@arbitrum/sdk/dist/lib/abi/factories/ArbOwner__factory";
import {
  envVars,
  getDeployersAndConfig,
  getProviders,
  isDeployingToNova,
  isLocalDeployment,
} from "./providerSetup";
import { assert, assertEquals, getProxyOwner } from "./testUtils";
import { ProxyAdmin__factory } from "../typechain-types";
import { Provider } from "@ethersproject/providers";
import { RollupCore } from "@arbitrum/sdk/dist/lib/abi/RollupCore";
import { L2Network } from "@arbitrum/sdk";
import {
  BeaconProxyFactory__factory,
  L1CustomGateway__factory,
  L1GatewayRouter__factory,
  L2ERC20Gateway__factory,
  UpgradeableBeacon__factory,
} from "../token-bridge-contracts/build/types";

const ARB_OWNER_PRECOMPILE = "0x000000000000000000000000000000000000006b";

/**
 * Verifies ownership of protocol contracts is successfully transferred to DAO
 */
export const verifyOwnership = async () => {
  const { arbNetwork, novaNetwork } = await getDeployersAndConfig();
  const { ethProvider, arbProvider, novaProvider } = await getProviders();

  const contractAddresses = require("../" + envVars.deployedContractsLocation);
  const l1Executor = contractAddresses["l1Executor"];
  const l2Executor = contractAddresses["l2Executor"];

  console.log("Verify ownership over Arb protocol contracts");
  const arbOneRollup = RollupCore__factory.connect(arbNetwork.ethBridge.rollup, ethProvider);
  await verifyProtocolOwnership(arbOneRollup, l1Executor, ethProvider);

  console.log("Verify ownership over Arb token bridge contracts");
  await verifyTokenBridgeOwnership(arbNetwork, l1Executor, l2Executor, ethProvider, arbProvider);

  if (!isLocalDeployment()) {
    // only check arbOwner precompile in production, atm ArbOwner's owner is set to address zero in test node
    console.log("Verify Arb chain owner");
    await verifyArbOwner(arbProvider, l2Executor);
  }

  if (isDeployingToNova()) {
    const novaExecutor = contractAddresses["novaUpgradeExecutorProxy"];

    console.log("Verify ownership over Nova protocol contracts");
    const novaRollup = RollupCore__factory.connect(novaNetwork!.ethBridge.rollup, ethProvider);
    await verifyProtocolOwnership(novaRollup, l1Executor, ethProvider);

    console.log("Verify ownership over Nova token bridge contracts");
    await verifyTokenBridgeOwnership(
      novaNetwork!,
      l1Executor,
      novaExecutor,
      ethProvider,
      novaProvider!
    );

    if (!isLocalDeployment()) {
      console.log("Verify Nova chain owner");
      await verifyArbOwner(novaProvider!, novaExecutor);
    }
  }
};

/**
 * Verify:
 * - L2 executor is chain owner
 */
async function verifyArbOwner(provider: Provider, l2Executor: string) {
  const ownerPrecompile = ArbOwner__factory.connect(ARB_OWNER_PRECOMPILE, provider);

  assert(await ownerPrecompile.isChainOwner(l2Executor), "L2Executor should be the chain owner");

  const owners: string[] = await ownerPrecompile.getAllChainOwners();
  assert(owners.length == 1, "There should be only 1 chain owner");
}

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

  //// check owner of L1 gatewayRouter and custom gateway
  const l1GatewayRouter = L1GatewayRouter__factory.connect(
    l2Network.tokenBridge.l1GatewayRouter,
    ethProvider
  );
  assertEquals(
    await l1GatewayRouter.owner(),
    l1Executor,
    "l1Executor should be l1GatewayRouter's owner"
  );

  const l1CustomGateway = L1CustomGateway__factory.connect(
    l2Network.tokenBridge.l1CustomGateway,
    ethProvider
  );
  assertEquals(
    await l1CustomGateway.owner(),
    l1Executor,
    "l1Executor should be l1GatewayRouter's owner"
  );

  //// check owner of L2 token bridge's proxyAdmins is L2 executor

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

  //// check Upgradeable Beacon's owner is L2 executor
  const l2Erc20Gw = L2ERC20Gateway__factory.connect(
    l2Network.tokenBridge.l2ERC20Gateway,
    l2Provider
  );
  const beaconProxyFactory = BeaconProxyFactory__factory.connect(
    await l2Erc20Gw.beaconProxyFactory(),
    l2Provider
  );
  const beacon = UpgradeableBeacon__factory.connect(await beaconProxyFactory.beacon(), l2Provider);
  assertEquals(await beacon.owner(), l2Executor, "l2Executor should be beacon's owner");
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
