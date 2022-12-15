import { BigNumber, ethers, Signer } from "ethers";
import { formatEther, formatUnits, parseEther } from "ethers/lib/utils";
import { TokenDistributor } from "../typechain-types";
import * as GovernanceConstants from "./governance.constants";
import { getProviders } from "./providerSetup";

const TOKEN_RECIPIENTS_FILE_NAME = "files/recipients.json";

/**
 * Sets airdrop recipients in batches. Batch is posted every 2sec, but if gas price gets
 * above base price we wait until it falls back to base gas price of 0.1 gwei.
 *
 * @param tokenDistributor
 * @param arbDeployer
 */
export async function setClaimRecipients(tokenDistributor: TokenDistributor, arbDeployer: Signer): Promise<number> {
  const tokenRecipientsByPoints = require("../" + TOKEN_RECIPIENTS_FILE_NAME);
  const { tokenRecipients, tokenAmounts } = mapPointsToAmounts(tokenRecipientsByPoints);

  // set recipients in batches
  const BATCH_SIZE = 100;
  const numOfBatches = Math.floor(tokenRecipients.length / BATCH_SIZE);

  // 0.1 gwei
  const BASE_GAS_PRICE = BigNumber.from(100000000);
  const firstBatch = GovernanceConstants.L2_NUM_OF_RECIPIENT_BATCHES_ALREADY_SET;
  let canClaimEventsEmitted = 0;
  for (let i = firstBatch; i <= numOfBatches; i++) {
    console.log("---- Batch ", i, "/", numOfBatches);

    let gasPriceBestGuess = await arbDeployer.provider!.getGasPrice();

    // if gas price raises above base price wait until if falls back
    if (gasPriceBestGuess.gt(BASE_GAS_PRICE)) {
      while (true) {
        console.log("Gas price too high: ", formatUnits(gasPriceBestGuess, "gwei"), " gwei");
        console.log("Sleeping 30 sec");
        // sleep 30 sec, then check if gas price has fallen down
        await new Promise((resolve) => setTimeout(resolve, 30000));

        // check if fell back to 0.1 gwei
        gasPriceBestGuess = await arbDeployer.provider!.getGasPrice();
        if (gasPriceBestGuess.eq(BASE_GAS_PRICE)) {
          break;
        }
      }
    }

    // generally sleep 2 seconds to keep TX fees from going up, and to avoid filling all the blockspace
    await new Promise((resolve) => setTimeout(resolve, 2000));

    let recipientsBatch: string[] = [];
    let amountsBatch: BigNumber[] = [];

    // slice batches
    if (i < numOfBatches) {
      recipientsBatch = tokenRecipients.slice(i * BATCH_SIZE, (i + 1) * BATCH_SIZE);
      amountsBatch = tokenAmounts.slice(i * BATCH_SIZE, (i + 1) * BATCH_SIZE);
    } else {
      if (tokenRecipients.length == numOfBatches * BATCH_SIZE) {
        // nothing left
        break;
      }
      // last remaining batch
      recipientsBatch = tokenRecipients.slice(i * BATCH_SIZE);
      amountsBatch = tokenAmounts.slice(i * BATCH_SIZE);
    }

    // set recipients
    const txReceipt = await (
      await tokenDistributor.setRecipients(recipientsBatch, amountsBatch)
    ).wait();

    // update event tracker
    canClaimEventsEmitted += txReceipt.logs.length;

    // print gas usage stats
    console.log("Gas used: ", txReceipt.gasUsed.toString());
    console.log(
      "Gas price in gwei: ",
      ethers.utils.formatUnits(txReceipt.effectiveGasPrice, "gwei")
    );
    console.log(
      "Gas cost in ETH: ",
      ethers.utils.formatUnits(txReceipt.gasUsed.mul(txReceipt.effectiveGasPrice), "ether")
    );
  }

  return canClaimEventsEmitted;
}

/**
 * Get number of recipients set by checking the number of 'CanClaim' events emitted.
 * Check in ranges of 100 blocks.
 *
 * @param tokenDistributor
 * @param startBlock
 * @param endBlock
 * @returns
 */
export async function getNumberOfRecipientsSetInBlockRange(
  tokenDistributor: TokenDistributor,
  startBlock: number,
  endBlock: number
): Promise<number> {
  let totalEvents = 0;
  const canClaimFilter = tokenDistributor.filters.CanClaim();

  let currentBlock = startBlock;
  // in 100 blocks there can be 100 recipient batches => 10k events at most
  const blocksToSearch = 100;
  while (true) {
    // query 100 blocks
    const canClaimEvents = await tokenDistributor.queryFilter(
      canClaimFilter,
      currentBlock,
      currentBlock + blocksToSearch
    );

    // keep track of number of events found
    totalEvents += canClaimEvents.length;

    // next 100 blocks
    currentBlock = currentBlock + blocksToSearch + 1;
    if (currentBlock > endBlock) {
      break;
    }
  }

  // just in case check if there was any CanClaim event since latest queried block
  const remainingEvents = await tokenDistributor.queryFilter(canClaimFilter, currentBlock);
  totalEvents += remainingEvents.length;

  return totalEvents;
}

/**
 * Map points to claimable token amount per account
 * @param tokenRecipientsByPoints
 */
function mapPointsToAmounts(tokenRecipientsByPoints: any) {
  let tokenRecipients: string[] = [];
  let tokenAmounts: BigNumber[] = [];

  for (const key in tokenRecipientsByPoints) {
    tokenRecipients.push(key);

    const points = tokenRecipientsByPoints[key].points;
    switch (points) {
      case 1:
      case 2:
      case 3: {
        tokenAmounts.push(parseEther("3000"));
        break;
      }
      case 4: {
        tokenAmounts.push(parseEther("4500"));
        break;
      }
      case 5: {
        tokenAmounts.push(parseEther("6000"));
        break;
      }
      case 6: {
        tokenAmounts.push(parseEther("9000"));
        break;
      }
      case 7: {
        tokenAmounts.push(parseEther("10500"));
        break;
      }
      case 8:
      case 9:
      case 10:
      case 11:
      case 12:
      case 13:
      case 14:
      case 15: {
        tokenAmounts.push(parseEther("12000"));
        break;
      }

      default: {
        throw new Error("Incorrect number of points for account " + key + ": " + points);
      }
    }
  }

  return { tokenRecipients, tokenAmounts };
}

export function printRecipientsInfo() {
  const tokenRecipientsByPoints = require("../" + TOKEN_RECIPIENTS_FILE_NAME);
  const { tokenRecipients, tokenAmounts } = mapPointsToAmounts(tokenRecipientsByPoints);

  let totalClaimable = BigNumber.from(0);
  tokenAmounts.forEach((element) => {
    totalClaimable = totalClaimable.add(element);
  });

  console.log("Number of token recipients:", tokenRecipients.length);
  console.log("Number of token to claim:", formatEther(totalClaimable));
}
