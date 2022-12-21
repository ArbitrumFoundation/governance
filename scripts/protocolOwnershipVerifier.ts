import { RollupCore__factory } from "@arbitrum/sdk/dist/lib/abi/factories/RollupCore__factory";
import { Bridge__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Bridge__factory";
import { Inbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Inbox__factory";
import { SequencerInbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/SequencerInbox__factory";
import { Outbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Outbox__factory";
import { ChallengeManager__factory } from "@arbitrum/sdk/dist/lib/abi/factories/ChallengeManager__factory";

import { getProviders } from "./providerSetup";
import { assertEquals, getProxyOwner } from "./testUtils";
import { ProxyAdmin__factory } from "../typechain-types";
import { Provider } from "@ethersproject/providers";
import { RollupCore } from "@arbitrum/sdk/dist/lib/abi/RollupCore";

const ROLLUP_ADDRESS = "0x5eF0D09d1E6204141B4d37530808eD19f60FBa35";
const L1_PROTOCOL_PROXY_ADMIN = "0x554723262467f125ac9e1cdfa9ce15cc53822dbd";
const L1_UPGRADE_EXECUTOR = "0xC234E41AE2cb00311956Aa7109fC801ae8c80941";

/**
 * Verifies ownership of protocol contracts is successfully transferred to DAO
 */
export const verifyOwnership = async () => {
  const { ethProvider } = await getProviders();

  const arbOneRollup = RollupCore__factory.connect(ROLLUP_ADDRESS, ethProvider);
  await verifyArbProtocolOwnership(arbOneRollup, ethProvider);
};

/**
 * Verify:
 * - bridge, inbox, seqInbox, outbox and challengeManager are owned by proxyAdmin
 * - proxyAdmin and rollup are owned by DAO (ownership transferred from multisig)
 */
async function verifyArbProtocolOwnership(arbOneRollup: RollupCore, ethProvider: Provider) {
  const arbL1Contracts = await getProtocolContracts(arbOneRollup, ethProvider);

  //// verify proxy admin

  assertEquals(
    await getProxyOwner(arbL1Contracts["bridge"].address, ethProvider),
    L1_PROTOCOL_PROXY_ADMIN,
    "L1_PROTOCOL_PROXY_ADMIN should be bridge's proxy admin"
  );
  assertEquals(
    await getProxyOwner(arbL1Contracts["inbox"].address, ethProvider),
    L1_PROTOCOL_PROXY_ADMIN,
    "L1_PROTOCOL_PROXY_ADMIN should be inbox's proxy admin"
  );
  assertEquals(
    await getProxyOwner(arbL1Contracts["sequencerInbox"].address, ethProvider),
    L1_PROTOCOL_PROXY_ADMIN,
    "L1_PROTOCOL_PROXY_ADMIN should be sequencerInbox's proxy admin"
  );
  assertEquals(
    await getProxyOwner(arbL1Contracts["outbox"].address, ethProvider),
    L1_PROTOCOL_PROXY_ADMIN,
    "L1_PROTOCOL_PROXY_ADMIN should be outbox's proxy admin"
  );
  assertEquals(
    await getProxyOwner(arbL1Contracts["challengeManager"].address, ethProvider),
    L1_PROTOCOL_PROXY_ADMIN,
    "L1_PROTOCOL_PROXY_ADMIN should be challengeManager's proxy admin"
  );

  //// verify ownership over rollup and proxyAdmin is transferred to DAO

  assertEquals(
    await getProxyOwner(arbL1Contracts["rollup"].address, ethProvider),
    L1_UPGRADE_EXECUTOR,
    "L1_UPGRADE_EXECUTOR should be L1GovernanceFactory's owner"
  );
  const proxyAdmin = ProxyAdmin__factory.connect(L1_PROTOCOL_PROXY_ADMIN, ethProvider);
  assertEquals(
    await proxyAdmin.owner(),
    L1_UPGRADE_EXECUTOR,
    "L1_UPGRADE_EXECUTOR should be challengeManager's proxy admin"
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
