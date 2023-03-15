import { ARB_GAS_INFO } from "@arbitrum/sdk/dist/lib/dataEntities/constants";
import { BigNumber, ethers, Signer } from "ethers";
import { formatEther, formatUnits, parseEther } from "ethers/lib/utils";
import { TokenDistributor } from "../typechain-types";
import { ArbGasInfo__factory } from "@arbitrum/sdk/dist/lib/abi/factories/ArbGasInfo__factory";
import { Recipients } from "./testUtils";

const validClaimAmounts: BigNumber[] = [
  parseEther("625"),
  parseEther("875"),
  parseEther("1125"),
  parseEther("1250"),
  parseEther("1500"),
  parseEther("1625"),
  parseEther("1750"),
  parseEther("1875"),
  parseEther("2000"),
  parseEther("2125"),
  parseEther("2250"),
  parseEther("2500"),
  parseEther("2750"),
  parseEther("3000"),
  parseEther("3125"),
  parseEther("3250"),
  parseEther("3375"),
  parseEther("3500"),
  parseEther("3625"),
  parseEther("3750"),
  parseEther("4000"),
  parseEther("4250"),
  parseEther("4500"),
  parseEther("4750"),
  parseEther("5000"),
  parseEther("5125"),
  parseEther("5250"),
  parseEther("5500"),
  parseEther("5750"),
  parseEther("6000"),
  parseEther("6250"),
  parseEther("6500"),
  parseEther("6750"),
  parseEther("7000"),
  parseEther("7250"),
  parseEther("8250"),
  parseEther("8500"),
  parseEther("8750"),
  parseEther("10250"),
];

/**
 * Sets airdrop recipients in batches. Batch is posted every 2sec, but if gas price gets
 * above base price we wait until it falls back to base gas price of 0.1 gwei.
 *
 * @param tokenDistributor
 * @param arbDeployer
 */
export async function setClaimRecipients(
  tokenDistributor: TokenDistributor,
  arbDeployer: Signer,
  claimRecipients: Recipients,
  config: {
    RECIPIENTS_BATCH_SIZE: number;
    BASE_L2_GAS_PRICE_LIMIT: number;
    BASE_L1_GAS_PRICE_LIMIT: number;
    GET_LOGS_BLOCK_RANGE: number;
    SLEEP_TIME_BETWEEN_RECIPIENT_BATCHES_IN_MS: number;
  },
  previousStartBlock?: number
): Promise<number> {
  // set recipients in batches
  let recipientsAlreadySet = 0;
  if (previousStartBlock) {
    const blockNow = await arbDeployer.provider!.getBlockNumber();
    const recipients = await getRecipientsDataFromContractEvents(
      tokenDistributor,
      previousStartBlock,
      blockNow,
      config
    );

    recipientsAlreadySet = Object.keys(recipients).length;
  }

  // 0.1 gwei
  const l2GasPriceLimit = BigNumber.from(config.BASE_L2_GAS_PRICE_LIMIT);
  // 15 gwei
  const l1GasPriceLimit = BigNumber.from(config.BASE_L1_GAS_PRICE_LIMIT);
  const arbGasInfo = ArbGasInfo__factory.connect(ARB_GAS_INFO, arbDeployer);

  // sort by value
  const { tokenRecipients, tokenAmounts } = getRecipientsAndAmountsSortedByAmounts(claimRecipients);
  verifyOrdering(claimRecipients, tokenRecipients, tokenAmounts);

  let canClaimEventsEmitted = 0;
  for (
    let i = recipientsAlreadySet;
    i < tokenRecipients.length;
    i = i + config.RECIPIENTS_BATCH_SIZE
  ) {
    console.log("---- Batch recipients", i, "-", i + config.RECIPIENTS_BATCH_SIZE);

    // if L1 or L2 are congested, wait until it clears out
    await waitForAcceptableGasPrice(l2GasPriceLimit, false, () =>
      arbDeployer.provider!.getGasPrice()
    );
    await waitForAcceptableGasPrice(l1GasPriceLimit, true, () => arbGasInfo.getL1BaseFeeEstimate());

    // sleep for a certain period to keep TX fees from going up and to avoid filling all the blockspace
    await new Promise((resolve) =>
      setTimeout(resolve, config.SLEEP_TIME_BETWEEN_RECIPIENT_BATCHES_IN_MS)
    );

    const recipientsBatch: string[] = tokenRecipients.slice(i, i + config.RECIPIENTS_BATCH_SIZE);
    const amountsBatch: BigNumber[] = tokenAmounts.slice(i, i + config.RECIPIENTS_BATCH_SIZE);

    if (!isAmountsBatchValid(amountsBatch)) {
      throw new Error("Unsupported claim amount!");
    }

    // set recipients
    const txReceipt = await (
      await tokenDistributor.setRecipients(recipientsBatch, amountsBatch)
    ).wait();

    // update event tracker
    canClaimEventsEmitted += txReceipt.logs.length;

    // print gas usage stats
    printGasUsageStats(txReceipt);
  }

  return canClaimEventsEmitted;
}

/**
 * Print amount of gas used, gas price and TX cost
 */
function printGasUsageStats(txReceipt: ethers.ContractReceipt) {
  console.log("Gas used: ", txReceipt.gasUsed.toString());
  console.log("Gas price in gwei: ", ethers.utils.formatUnits(txReceipt.effectiveGasPrice, "gwei"));
  console.log(
    "TX cost in ETH: ",
    ethers.utils.formatUnits(txReceipt.gasUsed.mul(txReceipt.effectiveGasPrice), "ether")
  );
}

/**
 * Wait until gas price is at acceptable levels.
 */
async function waitForAcceptableGasPrice(
  gasPriceLimit: BigNumber,
  isL1Gas: Boolean,
  gasPriceFetcher: () => Promise<BigNumber>
) {
  let gasPrice = await gasPriceFetcher();
  if (gasPrice.gt(gasPriceLimit)) {
    while (true) {
      const isL1 = isL1Gas ? "L1" : "L2";
      console.log(isL1, "gas price too high:", formatUnits(gasPrice, "gwei"), " gwei");
      console.log("Sleeping 30 sec");
      // sleep 30 sec, then check if gas price has fallen down
      await new Promise((resolve) => setTimeout(resolve, 30000));

      // check if fell back below the limit
      gasPrice = await gasPriceFetcher();
      if (gasPrice.lte(gasPriceLimit)) {
        break;
      }
    }
  }
}

/**
 * Scan the blocks between start and end block and collect all emitted 'CanClaim' events.
 *
 * @param tokenDistributor
 * @param startBlock
 * @param endBlock
 * @returns
 */
export async function getRecipientsDataFromContractEvents(
  tokenDistributor: TokenDistributor,
  startBlock: number,
  endBlock: number,
  config: {
    GET_LOGS_BLOCK_RANGE: number;
  }
): Promise<{ [key: string]: BigNumber }> {
  console.log(
    "Collecting CanClaim events from block",
    startBlock.toString(),
    "to block",
    endBlock.toString()
  );

  let recipientData: { [key: string]: BigNumber } = {};
  const canClaimFilter = tokenDistributor.filters.CanClaim();

  let currentBlock = startBlock;
  // in 100 blocks there can be 100 recipient batches => 10k events at most
  const blocksToSearch = config.GET_LOGS_BLOCK_RANGE;
  while (currentBlock <= endBlock) {
    // query 100 blocks
    const canClaimEvents = await tokenDistributor.queryFilter(
      canClaimFilter,
      currentBlock,
      currentBlock + blocksToSearch
    );

    // collect recipient-amount pairs
    canClaimEvents.map((event) => (recipientData[event.args[0]] = event.args[1]));

    // next 100 blocks
    currentBlock = currentBlock + blocksToSearch + 1;
  }

  console.log("Done, found", Object.keys(recipientData).length, "recipients");
  return recipientData;
}

export function printRecipientsInfo(claimRecipients: Recipients) {
  const totalClaimable = Object.values(claimRecipients).reduce((a, b) => a.add(b));

  console.log("Number of token recipients:", Object.keys(claimRecipients).length);
  console.log("Number of token to claim:", formatEther(totalClaimable));
}

/**
 * Check if amount is among the supported ones
 * @param amount
 * @returns
 */
export function isClaimAmountValid(amount: BigNumber) {
  return (
    amount.lt(ethers.constants.MaxUint256) &&
    validClaimAmounts.some((elem) => elem.toString() == amount.toString())
  );
}

/**
 * Check if every amount is the supported one
 * @param amounts
 * @returns
 */
export function isAmountsBatchValid(amounts: BigNumber[]) {
  return amounts.every((elem) => isClaimAmountValid(elem));
}

/**
 * Sort recipients-amounts pairs by amounts and return them as 2 arrays
 *
 * @param recipients
 * @returns
 */
function getRecipientsAndAmountsSortedByAmounts(recipients: Recipients): {
  tokenRecipients: string[];
  tokenAmounts: BigNumber[];
} {
  // recipient - amount pairs
  const pairs = Object.entries(recipients);

  const compareByAmount = (a: [string, BigNumber], b: [string, BigNumber]): number => {
    const amountA: BigNumber = a[1];
    const amountB: BigNumber = b[1];

    if (amountA.gt(amountB)) {
      return 1;
    }
    if (amountA.lt(amountB)) {
      return -1;
    }
    return 0;
  };

  pairs.sort(compareByAmount);

  const tokenRecipients: string[] = pairs.map((tuple) => tuple[0]);
  const tokenAmounts: BigNumber[] = pairs.map((tuple) => tuple[1]);

  return { tokenRecipients, tokenAmounts };
}

/**
 * Check that amounts are sorted and that recipient to amount mapping is preserved.
 * Throw error if an issue is found.
 *
 * @param claimRecipients
 * @param tokenRecipients
 * @param tokenAmounts
 */
function verifyOrdering(
  claimRecipients: Recipients,
  tokenRecipients: string[],
  tokenAmounts: BigNumber[]
) {
  for (let i = 0; i < tokenAmounts.length - 1; i++) {
    const amount = tokenAmounts[i];
    if (amount.gt(tokenAmounts[i + 1])) {
      throw new Error("Token amounts are exepected to be ordered");
    }

    const recipient = tokenRecipients[i];
    if (claimRecipients[recipient] !== amount) {
      throw new Error(
        `Mismatch between token ${recipient} recipient and token amount ${amount.toString()}`
      );
    }
  }
}
