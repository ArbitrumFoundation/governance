import { ethers, BigNumber } from "ethers";
import * as fs from "fs";
import * as path from "path";
import {
  ARB_TOKEN,
  EXCLUDE_ADDRESS,
  DELEGATE_CHECKPOINTS_SLOT,
  TOTAL_DELEGATION_SLOT,
  toQuantity,
  rlpHeader,
  calcMappingSlot,
  calcArraySlot,
  findLatestLog,
} from "./util";

// Captures a self-consistent L2StateMirror proof snapshot into l2_state_mirror.json, consumed by
// test/l1-voting/L2StateMirror.t.sol and VotingTokenMirror.t.sol. The snapshot is tied to the Arb
// One rollup's newest created assertion (confirmation doesn't matter: the tests replay the
// assertion hash through a MockRollup): we read the assertion, pin the L2 block it commits to,
// and capture the token and delegate-mapping account/storage/votes proofs at that block.
//
// Run after `forge build` (needs the rollup ABI artifact) with:
// ETH_URL=<l1 rpc> ARB_URL=<l2 rpc> yarn gen:l1-voting-fixtures

const ROLLUP = "0x4DCeB440657f21083db8aDd07665f8ddBe1DCfc0"; // Arb One rollup (on L1)

// Minimal mapping(address => address) contract deployed on Arb One to stand in for the L2
// DelegateMapping, with a single constructor-set entry: DELEGATE -> 0xdEaD. DELEGATE is a live
// whale delegate, so its ARB vote checkpoints stay provable alongside its mapping entry.
const DELEGATE_MAPPING = "0xfCFB1D88075A2478c8DD324c5b314cE721218817";
const DELEGATE_MAPPING_MAP_SLOT = 0;
const DELEGATE = "0xb4c064f466931B8d0F637654c916E3F203c46f13";

const OUT_FILE = path.join(__dirname, "l2_state_mirror.json");
const ROLLUP_ABI_FILE = path.join(__dirname, "../../../out/IRollupCore.sol/IRollupCore.json");

const ARB_ABI = [
  "function getVotes(address) view returns (uint256)",
  "function getTotalDelegation() view returns (uint256)",
];

// Read the rollup's newest created assertion and the L2 block hash it commits to.
async function getLatestCreatedAssertion(l1: ethers.providers.JsonRpcProvider) {
  if (!fs.existsSync(ROLLUP_ABI_FILE)) {
    throw new Error(`missing rollup ABI at ${ROLLUP_ABI_FILE}; run 'forge build' first`);
  }
  const abi = JSON.parse(fs.readFileSync(ROLLUP_ABI_FILE, "utf8")).abi;
  const iface = new ethers.utils.Interface(abi);

  const topic = iface.getEventTopic("AssertionCreated");
  const log = await findLatestLog(l1, { address: ROLLUP, topics: [topic] }, "AssertionCreated");

  const args = iface.parseLog(log).args;
  const after = args.assertion.afterState;
  return {
    assertionHash: args.assertionHash as string,
    parentAssertionHash: args.parentAssertionHash as string,
    inboxAcc: args.afterInboxBatchAcc as string,
    l2BlockHash: after.globalState.bytes32Vals[0] as string,
    sendRoot: after.globalState.bytes32Vals[1] as string,
    inboxPosition: (after.globalState.u64Vals[0] as BigNumber).toNumber(),
    positionInMessage: (after.globalState.u64Vals[1] as BigNumber).toNumber(),
    machineStatus: after.machineStatus as number,
    endHistoryRoot: after.endHistoryRoot as string,
  };
}

async function main() {
  const l1Rpc = process.env.ETH_URL;
  const l2Rpc = process.env.ARB_URL;
  if (!l1Rpc) throw new Error("ETH_URL not set");
  if (!l2Rpc) throw new Error("ARB_URL not set");
  const l1 = new ethers.providers.JsonRpcProvider(l1Rpc);
  const l2 = new ethers.providers.JsonRpcProvider(l2Rpc);
  const arb = new ethers.Contract(ARB_TOKEN, ARB_ABI, l2);

  // 1. newest created assertion + the L2 block it commits to
  const assertion = await getLatestCreatedAssertion(l1);
  const block = await l2.send("eth_getBlockByHash", [assertion.l2BlockHash, false]);
  const blockNumber = Number(block.number);
  console.log(`Newest created assertion ${assertion.assertionHash} -> L2 block ${blockNumber}`);

  // 2. block header RLP -> must reproduce the assertion's L2 block hash
  const blockHeaderRlp = rlpHeader(block);
  const computedHash = ethers.utils.keccak256(blockHeaderRlp);
  if (computedHash !== assertion.l2BlockHash) {
    throw new Error(`block hash mismatch: computed ${computedHash} != ${assertion.l2BlockHash} (header field set may have changed)`);
  }

  // 3. slot-calc chains for the two checkpoint arrays we prove the last element of: the exclude
  //    address's votes checkpoints (mapping) and the token's total delegation history (a plain array).
  const checkpointArrSlot = calcMappingSlot(DELEGATE_CHECKPOINTS_SLOT, EXCLUDE_ADDRESS);
  const checkpointsLength = BigNumber.from(await l2.getStorageAt(ARB_TOKEN, checkpointArrSlot, blockNumber));
  if (checkpointsLength.isZero()) throw new Error("exclude address has no checkpoints at this block");
  const lastCheckpointSlot = calcArraySlot(checkpointArrSlot, checkpointsLength.sub(1));

  const totalDelegationSlot = BigNumber.from(TOTAL_DELEGATION_SLOT);
  const totalDelegationLength = BigNumber.from(await l2.getStorageAt(ARB_TOKEN, totalDelegationSlot, blockNumber));
  if (totalDelegationLength.isZero()) throw new Error("total delegation history is empty at this block");
  const totalDelegationLastSlot = calcArraySlot(totalDelegationSlot, totalDelegationLength.sub(1));

  // 4. the fixture delegate: prove its votes checkpoints in the token and its claimed L1 address
  //    in the delegate mapping
  const delegateCheckpointArrSlot = calcMappingSlot(DELEGATE_CHECKPOINTS_SLOT, DELEGATE);
  const delegateCheckpointsLength = BigNumber.from(
    await l2.getStorageAt(ARB_TOKEN, delegateCheckpointArrSlot, blockNumber)
  );
  if (delegateCheckpointsLength.isZero()) throw new Error("delegate has no checkpoints at this block");
  const delegateLastCheckpointSlot = calcArraySlot(delegateCheckpointArrSlot, delegateCheckpointsLength.sub(1));

  // 5. token account + storage proofs (raw eth_getProof node arrays) for the six proven token slots
  const tokenSlots = [
    checkpointArrSlot,
    lastCheckpointSlot,
    totalDelegationSlot,
    totalDelegationLastSlot,
    delegateCheckpointArrSlot,
    delegateLastCheckpointSlot,
  ];
  const tokenProof = await l2.send("eth_getProof", [ARB_TOKEN, tokenSlots.map((s) => s.toHexString()), toQuantity(blockNumber)]);
  for (let i = 0; i < tokenSlots.length; i++) {
    if (BigNumber.from(tokenProof.storageProof[i].value).isZero()) {
      throw new Error(`slot ${tokenSlots[i].toHexString()} is zero; OP SecureMerkleTrie reverts on exclusion proofs`);
    }
  }

  // 6. delegate mapping account + storage proof for the delegate's entry
  const delegateL1AddressSlot = calcMappingSlot(DELEGATE_MAPPING_MAP_SLOT, DELEGATE);
  const mappingProof = await l2.send("eth_getProof", [DELEGATE_MAPPING, [delegateL1AddressSlot.toHexString()], toQuantity(blockNumber)]);
  if (BigNumber.from(mappingProof.storageProof[0].value).isZero()) {
    throw new Error(
      `delegate mapping entry is zero at block ${blockNumber}; if the mapping was deployed after ` +
        `this assertion's L2 block, retry once the next assertion is created`
    );
  }

  // 7. cross-checks against the live contracts (validates slots + the checkpoint-value shift)
  const lastCheckpointValue = BigNumber.from(tokenProof.storageProof[1].value);
  const votes = lastCheckpointValue.shr(32);
  const totalDelegationLastValue = BigNumber.from(tokenProof.storageProof[3].value);
  const totalDelegation = totalDelegationLastValue.shr(32);
  const liveVotes: BigNumber = await arb.getVotes(EXCLUDE_ADDRESS, { blockTag: blockNumber });
  const liveTotalDelegation: BigNumber = await arb.getTotalDelegation({ blockTag: blockNumber });
  if (!votes.eq(liveVotes)) throw new Error(`votes mismatch: ${votes} != getVotes ${liveVotes} (DELEGATE_CHECKPOINTS_SLOT wrong?)`);
  if (!totalDelegation.eq(liveTotalDelegation)) {
    throw new Error(`total delegation mismatch: ${totalDelegation} != getTotalDelegation ${liveTotalDelegation} (TOTAL_DELEGATION_SLOT wrong?)`);
  }

  const delegateVotes = BigNumber.from(tokenProof.storageProof[5].value).shr(32);
  const liveDelegateVotes: BigNumber = await arb.getVotes(DELEGATE, { blockTag: blockNumber });
  if (!delegateVotes.eq(liveDelegateVotes)) {
    throw new Error(`delegate votes mismatch: ${delegateVotes} != getVotes ${liveDelegateVotes}`);
  }
  const delegateL1Address = ethers.utils.getAddress(
    ethers.utils.hexZeroPad(BigNumber.from(mappingProof.storageProof[0].value).toHexString(), 20)
  );
  const mapping = new ethers.Contract(
    DELEGATE_MAPPING, ["function map(address) view returns (address)"], l2
  );
  const liveClaim: string = await mapping.map(DELEGATE, { blockTag: blockNumber });
  if (delegateL1Address !== liveClaim) {
    throw new Error(`claim mismatch: ${delegateL1Address} != map ${liveClaim} (DELEGATE_MAPPING_MAP_SLOT wrong?)`);
  }

  const fixture = {
    rollup: ethers.utils.getAddress(ROLLUP),
    assertionHash: assertion.assertionHash,
    parentAssertionHash: assertion.parentAssertionHash,
    inboxAcc: assertion.inboxAcc,
    l2BlockHash: assertion.l2BlockHash,
    sendRoot: assertion.sendRoot,
    inboxPosition: assertion.inboxPosition,
    positionInMessage: assertion.positionInMessage,
    machineStatus: assertion.machineStatus,
    endHistoryRoot: assertion.endHistoryRoot,
    blockHeaderRlp,
    blockNumber,
    stateRoot: block.stateRoot,
    l2TokenAddress: ethers.utils.getAddress(ARB_TOKEN),
    accountProof: tokenProof.accountProof,
    storageRoot: tokenProof.storageHash,
    delegateCheckpointsSlot: DELEGATE_CHECKPOINTS_SLOT,
    excludeAddress: ethers.utils.getAddress(EXCLUDE_ADDRESS),
    checkpointArrSlot: checkpointArrSlot.toHexString(),
    checkpointLenProof: tokenProof.storageProof[0].proof,
    checkpointsLength: checkpointsLength.toNumber(),
    lastCheckpointSlot: lastCheckpointSlot.toHexString(),
    lastCheckpointProof: tokenProof.storageProof[1].proof,
    lastCheckpointValue: lastCheckpointValue.toHexString(),
    expectedVotes: votes.toHexString(),
    totalDelegationSlot: TOTAL_DELEGATION_SLOT,
    totalDelegationLenProof: tokenProof.storageProof[2].proof,
    totalDelegationLength: totalDelegationLength.toNumber(),
    totalDelegationLastCheckpointSlot: totalDelegationLastSlot.toHexString(),
    totalDelegationLastCheckpointProof: tokenProof.storageProof[3].proof,
    totalDelegationLastCheckpointValue: totalDelegationLastValue.toHexString(),
    expectedTotalDelegation: totalDelegation.toHexString(),
    l2DelegateMappingAddress: ethers.utils.getAddress(DELEGATE_MAPPING),
    l2DelegateMappingL1AddressSlot: DELEGATE_MAPPING_MAP_SLOT,
    delegateMappingAccountProof: mappingProof.accountProof,
    delegateMappingStorageRoot: mappingProof.storageHash,
    delegateAccount: ethers.utils.getAddress(DELEGATE),
    delegateCheckpointLenProof: tokenProof.storageProof[4].proof,
    delegateLastCheckpointProof: tokenProof.storageProof[5].proof,
    expectedDelegateVotes: delegateVotes.toHexString(),
    delegateL1AddressProof: mappingProof.storageProof[0].proof,
    expectedDelegateL1Address: delegateL1Address,
  };

  fs.writeFileSync(OUT_FILE, JSON.stringify(fixture, null, 2) + "\n");
  console.log(
    `Wrote ${OUT_FILE} (votes=${votes.toString()}, totalDelegation=${totalDelegation.toString()}, delegate=${DELEGATE}, delegateVotes=${delegateVotes.toString()}, delegateL1Address=${delegateL1Address})`
  );
}

main().then(() => console.log("Done."));
