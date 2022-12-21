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

const ARB_ROLLUP_ADDRESS = "0x5eF0D09d1E6204141B4d37530808eD19f60FBa35";
const NOVA_ROLLUP_ADDRESS = "0xFb209827c58283535b744575e11953DCC4bEAD88";
const ARB_PROTOCOL_PROXY_ADMIN = "0x554723262467f125ac9e1cdfa9ce15cc53822dbd";
const NOVA_PROTOCOL_PROXY_ADMIN = "0x71D78dC7cCC0e037e12de1E50f5470903ce37148";
const L1_UPGRADE_EXECUTOR = "0xC234E41AE2cb00311956Aa7109fC801ae8c80941";

/**
 * Verifies ownership of protocol contracts is successfully transferred to DAO
 */
export const verifyOwnership = async () => {
  const { ethProvider } = await getProviders();

  console.log("Verify ownership over Arb protocol contracts");
  const arbOneRollup = RollupCore__factory.connect(ARB_ROLLUP_ADDRESS, ethProvider);
  await verifyProtocolOwnership(arbOneRollup, ARB_PROTOCOL_PROXY_ADMIN, ethProvider);

  console.log("Verify ownership over Nova protocol contracts");
  const novaRollup = RollupCore__factory.connect(NOVA_ROLLUP_ADDRESS, ethProvider);
  await verifyProtocolOwnership(novaRollup, NOVA_PROTOCOL_PROXY_ADMIN, ethProvider);
};

/**
 * Verify:
 * - bridge, inbox, seqInbox, outbox and challengeManager are owned by proxyAdmin
 * - proxyAdmin and rollup are owned by DAO (ownership transferred from multisig)
 */
async function verifyProtocolOwnership(
  rollupCore: RollupCore,
  proxyAdmin: string,
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
    L1_UPGRADE_EXECUTOR,
    "L1_UPGRADE_EXECUTOR should be L1GovernanceFactory's owner"
  );
  const proxyAdminContract = ProxyAdmin__factory.connect(proxyAdmin, ethProvider);
  assertEquals(
    await proxyAdminContract.owner(),
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
