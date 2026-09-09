import { ethers, BigNumber } from "ethers";
import * as fs from "fs";
import * as path from "path";
import {
  ARB_TOKEN,
  EXCLUDE_ADDRESS,
  DELEGATE_CHECKPOINTS_SLOT,
  toQuantity,
  rlpHeader,
  calcMappingSlot,
  calcArraySlot,
} from "./util";

// Captures real Arb One ARB-token proof data into proof_helper.json, consumed by
// test/l1-voting/ProofHelper.t.sol. Regenerate all l1-voting fixtures with: ARB_URL=<rpc> yarn
// gen:l1-voting-fixtures. Run directly (ARB_URL=<rpc> ts-node genProofFixture.ts [block]) to pin a block.

// proof_helper.json just needs real inclusion proofs; 53 is a known non-zero ARB storage slot.
const SLOTS = [53, 0];

// Deterministic unused address: it never delegated (zero checkpoints-length slot -> storage
// exclusion proof) and has no balance/nonce/code (absent from the state trie -> account exclusion
// proof). The OP SecureMerkleTrie verifies inclusion only, so both proofs must revert.
const ABSENT_ACCOUNT = ethers.utils.getAddress(
  "0x" + ethers.utils.id("l1-voting absent account").slice(26)
);

const OUT_FILE = path.join(__dirname, "proof_helper.json");

async function main() {
  const rpc = process.env.ARB_URL;
  if (!rpc) throw new Error("ARB_URL not set");
  const provider = new ethers.providers.JsonRpcProvider(rpc);

  const arg = process.argv[2];
  // a numeric arg is a block number (needs 0x); otherwise it's a named tag (latest/finalized/...)
  const tag = !arg ? "finalized" : /^\d+$/.test(arg) ? toQuantity(Number(arg)) : arg;
  const block = await provider.send("eth_getBlockByNumber", [tag, false]);
  const blockNumber = Number(block.number);
  console.log(`Pinning Arb One block ${blockNumber} (${tag})`);

  // 1. block header RLP -> verify it reproduces the canonical block hash
  const blockHeaderRlp = rlpHeader(block);
  const computedHash = ethers.utils.keccak256(blockHeaderRlp);
  if (computedHash !== block.hash) {
    throw new Error(`block hash mismatch: computed ${computedHash} != ${block.hash} (header field set may have changed)`);
  }

  // 2. account + storage proofs for the ARB token (raw eth_getProof node arrays)
  const proof = await provider.send("eth_getProof", [ARB_TOKEN, SLOTS.map(toQuantity), block.number]);
  for (let i = 0; i < SLOTS.length; i++) {
    if (BigNumber.from(proof.storageProof[i].value).isZero()) {
      throw new Error(`slot ${SLOTS[i]} is zero; OP SecureMerkleTrie reverts on exclusion proofs, pick a non-zero slot`);
    }
  }

  // 3. slot-calc chain + getVotes cross-check (validates DELEGATE_CHECKPOINTS_SLOT)
  const mSlot = calcMappingSlot(DELEGATE_CHECKPOINTS_SLOT, EXCLUDE_ADDRESS);
  const checkpointsLength = BigNumber.from(await provider.getStorageAt(ARB_TOKEN, mSlot, blockNumber));
  if (checkpointsLength.isZero()) throw new Error("exclude address has no checkpoints at this block");
  const vSlot = calcArraySlot(mSlot, checkpointsLength.sub(1));
  const lastCheckpointValue = BigNumber.from(await provider.getStorageAt(ARB_TOKEN, vSlot, blockNumber));

  const arb = new ethers.Contract(ARB_TOKEN, ["function getVotes(address) view returns (uint256)"], provider);
  const votes: BigNumber = await arb.getVotes(EXCLUDE_ADDRESS, { blockTag: blockNumber });
  if (!lastCheckpointValue.shr(32).eq(votes)) {
    throw new Error(`votes mismatch: lastCheckpoint>>32 ${lastCheckpointValue.shr(32)} != getVotes ${votes} (DELEGATE_CHECKPOINTS_SLOT wrong?)`);
  }

  // 4. exclusion proofs: the absent account's checkpoints-length slot in the token's storage
  //    trie, and the absent account itself in the state trie
  const zeroSlot = calcMappingSlot(DELEGATE_CHECKPOINTS_SLOT, ABSENT_ACCOUNT);
  const zeroProof = await provider.send("eth_getProof", [ARB_TOKEN, [zeroSlot.toHexString()], block.number]);
  if (!BigNumber.from(zeroProof.storageProof[0].value).isZero()) {
    throw new Error(`slot for ${ABSENT_ACCOUNT} is non-zero; pick an account with no checkpoints`);
  }

  const emptyCodeHash = ethers.utils.keccak256("0x");
  const absentProof = await provider.send("eth_getProof", [ABSENT_ACCOUNT, [], block.number]);
  if (
    !BigNumber.from(absentProof.balance).isZero() ||
    !BigNumber.from(absentProof.nonce).isZero() ||
    (absentProof.codeHash !== ethers.constants.HashZero && absentProof.codeHash !== emptyCodeHash)
  ) {
    throw new Error(`${ABSENT_ACCOUNT} exists in the state trie; pick an unused address`);
  }

  const fixture = {
    blockNumber,
    blockHash: block.hash,
    stateRoot: block.stateRoot,
    blockHeaderRlp,
    account: ethers.utils.getAddress(ARB_TOKEN),
    accountProof: proof.accountProof,
    storageRoot: proof.storageHash,
    slot0: SLOTS[0],
    slot0Value: proof.storageProof[0].value,
    slot0Proof: proof.storageProof[0].proof,
    slot1: SLOTS[1],
    slot1Value: proof.storageProof[1].value,
    slot1Proof: proof.storageProof[1].proof,
    delegateCheckpointsSlot: DELEGATE_CHECKPOINTS_SLOT,
    excludeAddress: ethers.utils.getAddress(EXCLUDE_ADDRESS),
    expectedMappingSlot: mSlot.toHexString(),
    checkpointsLength: checkpointsLength.toNumber(),
    expectedArraySlot: vSlot.toHexString(),
    lastCheckpointValue: lastCheckpointValue.toHexString(),
    expectedVotes: votes.toHexString(),
    zeroSlot: zeroSlot.toHexString(),
    zeroSlotProof: zeroProof.storageProof[0].proof,
    absentAccount: ABSENT_ACCOUNT,
    absentAccountProof: absentProof.accountProof,
  };

  fs.writeFileSync(OUT_FILE, JSON.stringify(fixture, null, 2) + "\n");
  console.log(`Wrote ${OUT_FILE} (votes=${votes.toString()}, checkpoints=${checkpointsLength.toString()})`);
}

main().then(() => console.log("Done."));
