import { RollupCore__factory } from "@arbitrum/sdk/dist/lib/abi/factories/RollupCore__factory";
import { Bridge__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Bridge__factory";
import { Inbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Inbox__factory";
import { SequencerInbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/SequencerInbox__factory";
import { Outbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Outbox__factory";
import { ChallengeManager__factory } from "@arbitrum/sdk/dist/lib/abi/factories/ChallengeManager__factory";

import { getProviders } from "./providerSetup";
import { assertEquals, getProxyOwner } from "./testUtils";

const ROLLUP_ADDRESS = "0x5eF0D09d1E6204141B4d37530808eD19f60FBa35";
const L1_PROTOCOL_PROXY_ADMIN = "0x554723262467f125ac9e1cdfa9ce15cc53822dbd";

/**
 * Verifies ownership of protocol contracts is successfully transferred to DAO
 */
export const verifyOwnership = async () => {
  const { ethProvider } = await getProviders();

  const rollup = RollupCore__factory.connect(ROLLUP_ADDRESS, ethProvider);
  const bridge = Bridge__factory.connect(await rollup.bridge(), ethProvider);
  const inbox = Inbox__factory.connect(await rollup.inbox(), ethProvider);
  const sequencerInbox = SequencerInbox__factory.connect(
    await rollup.sequencerInbox(),
    ethProvider
  );
  const outbox = Outbox__factory.connect(await rollup.outbox(), ethProvider);
  const challengeManager = ChallengeManager__factory.connect(
    await rollup.challengeManager(),
    ethProvider
  );


  //// verify proxy admin 

  assertEquals(
    await getProxyOwner(bridge.address, ethProvider),
    L1_PROTOCOL_PROXY_ADMIN,
    "L1_PROTOCOL_PROXY_ADMIN should be bridge's proxy admin"
  );
  assertEquals(
    await getProxyOwner(inbox.address, ethProvider),
    L1_PROTOCOL_PROXY_ADMIN,
    "L1_PROTOCOL_PROXY_ADMIN should be inbox's proxy admin"
  );
  assertEquals(
    await getProxyOwner(sequencerInbox.address, ethProvider),
    L1_PROTOCOL_PROXY_ADMIN,
    "L1_PROTOCOL_PROXY_ADMIN should be sequencerInbox's proxy admin"
  );
  assertEquals(
    await getProxyOwner(outbox.address, ethProvider),
    L1_PROTOCOL_PROXY_ADMIN,
    "L1_PROTOCOL_PROXY_ADMIN should be outbox's proxy admin"
  );
  assertEquals(
    await getProxyOwner(challengeManager.address, ethProvider),
    L1_PROTOCOL_PROXY_ADMIN,
    "L1_PROTOCOL_PROXY_ADMIN should be challengeManager's proxy admin"
  );
};

async function main() {
  console.log("Start verification process...");
  await verifyOwnership();
}

main().then(() => console.log("Done."));
