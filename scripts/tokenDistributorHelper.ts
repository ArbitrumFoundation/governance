import { ARB_GAS_INFO } from "@arbitrum/sdk/dist/lib/dataEntities/constants";
import { BigNumber, ethers, Signer } from "ethers";
import { formatEther, formatUnits, parseEther } from "ethers/lib/utils";
import { TokenDistributor } from "../typechain-types";
import { ArbGasInfo__factory } from "@arbitrum/sdk/dist/lib/abi/factories/ArbGasInfo__factory";
import { Recipients } from "./testUtils";

const validClaimAmounts: BigNumber[] = [
  parseEther("1200"),
  parseEther("1700"),
  parseEther("2200"),
  parseEther("3200"),
  parseEther("3700"),
  parseEther("4200"),
  parseEther("6200"),
  parseEther("6700"),
  parseEther("7200"),
  parseEther("10200"),
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

  // first sort by value to improve compression
  const sortedRecipients = sortRecipientsByValue(claimRecipients);
  const tokenRecipients = Object.keys(sortedRecipients);
  const tokenAmounts = Object.values(sortedRecipients);

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

    // generally sleep 2 seconds to keep TX fees from going up, and to avoid filling all the blockspace
    await new Promise((resolve) => setTimeout(resolve, 2000));

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

export function sortRecipientsByValue(recipients: Recipients) {
  const pairs = Object.entries(recipients);
  const compareBigNumbers = (a: [string, BigNumber], b: [string, BigNumber]): number => {
    return a[1].sub(b[1]).div(BigNumber.from(10).pow(18)).toNumber();
  };

  pairs.sort(compareBigNumbers);

  const sortedRecipients: Recipients = pairs.reduce((obj: Recipients, [key, value]) => {
    obj[key] = value;
    return obj;
  }, {});

  return sortedRecipients;
}
