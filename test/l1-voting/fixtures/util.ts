import { ethers, BigNumber } from "ethers";

// Shared constants + helpers for the l1-voting fixture generators (genProofFixture.ts, genVotesMirrorFixture.ts).

const ARB_TOKEN = "0x912CE59144191C1204E64559FE8253a0e49E6548";
// The "exclude" address always has a non-zero last checkpoint, so it stays provable (see L2StateMirror).
const EXCLUDE_ADDRESS = "0x00000000000000000000000000000000000A4B86";
const DELEGATE_CHECKPOINTS_SLOT = 255;
const TOTAL_DELEGATION_SLOT = 356;

// findLatestLog widens its lookback from the chain tip in steps of LOG_LOOKBACK_STEP blocks, up to
// LOG_LOOKBACK_MAX, until a matching log appears.
const LOG_LOOKBACK_STEP = 100_000;
const LOG_LOOKBACK_MAX = 500_000;

export {
  ARB_TOKEN,
  EXCLUDE_ADDRESS,
  DELEGATE_CHECKPOINTS_SLOT,
  TOTAL_DELEGATION_SLOT,
  LOG_LOOKBACK_STEP,
  LOG_LOOKBACK_MAX,
};

export function toQuantity(n: number): string {
  return "0x" + n.toString(16);
}

// JSON-RPC quantities omit leading nibbles; pad to whole bytes so RLP sees real byte strings.
export function padToWholeBytes(hex: string): string {
  let h = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (h.length % 2 !== 0) h = "0" + h;
  return "0x" + h;
}

export function rlpHeader(block: any): string {
  const fields = [
    block.parentHash,
    block.sha3Uncles,
    block.miner,
    block.stateRoot,
    block.transactionsRoot,
    block.receiptsRoot,
    block.logsBloom,
    block.difficulty,
    block.number,
    block.gasLimit,
    block.gasUsed,
    block.timestamp,
    block.extraData,
    block.mixHash,
    block.nonce,
    block.baseFeePerGas,
  ].map(padToWholeBytes);
  return ethers.utils.RLP.encode(fields);
}

export function calcMappingSlot(mapSlot: number, addr: string): BigNumber {
  return BigNumber.from(
    ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [ethers.utils.getAddress(addr), mapSlot])
    )
  );
}

export function calcArraySlot(arraySlot: BigNumber, index: BigNumber): BigNumber {
  return BigNumber.from(ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(["uint256"], [arraySlot]))).add(index);
}

// Find the most recent log matching `filter`, widening the lookback window from the chain tip
// until one appears. `description` labels the log in the error if none is found.
export async function findLatestLog(
  provider: ethers.providers.JsonRpcProvider,
  filter: { address: string; topics: (string | null)[] },
  description: string
): Promise<ethers.providers.Log> {
  const tip = await provider.getBlockNumber();
  let logs: ethers.providers.Log[] = [];
  for (let span = LOG_LOOKBACK_STEP; span <= LOG_LOOKBACK_MAX && logs.length === 0; span += LOG_LOOKBACK_STEP) {
    logs = await provider.getLogs({ ...filter, fromBlock: tip - span, toBlock: tip });
  }
  if (logs.length === 0) {
    throw new Error(`no logs found (${description})`);
  }
  return logs[logs.length - 1];
}
