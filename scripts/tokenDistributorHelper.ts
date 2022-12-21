import { BigNumber, ethers, Signer } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { TokenDistributor } from "../typechain-types";

const TOKEN_RECIPIENTS_FILE_NAME = "files/recipients.json";

/**
 * Sets airdrop recipients in batches. Batch is posted every 2sec, but if gas price gets
 * above base price we wait until it falls back to base gas price of 0.1 gwei.
 *
 * @param tokenDistributor
 * @param arbDeployer
 */
export async function setClaimRecipients(
  tokenDistributor: TokenDistributor,
  arbDeployer: Signer
) {
  const tokenRecipientsByPoints = require("../" + TOKEN_RECIPIENTS_FILE_NAME);
  const { tokenRecipients, tokenAmounts } = mapPointsToAmounts(tokenRecipientsByPoints);

  // set recipients in batches
  const BATCH_SIZE = 2;
  const recipientsAlreadySet = await getNumberOfRecipientsSet(tokenDistributor);

  // 0.1 gwei
  const BASE_GAS_PRICE = BigNumber.from(100000000);
  for (
    let i = recipientsAlreadySet;
    i < tokenRecipients.length;
    i = i + BATCH_SIZE
  ) {
    console.log("---- Batch recipients", i, "-", i + BATCH_SIZE);

    let gasPriceBestGuess = await arbDeployer.provider!.getGasPrice();

    // if gas price raises above base price wait until if falls back
    if (gasPriceBestGuess.gt(BASE_GAS_PRICE)) {
      while (true) {
        console.log(
          "Gas price too high: ",
          ethers.utils.formatUnits(gasPriceBestGuess, "gwei"),
          " gwei"
        );
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

    const recipientsBatch: string[] = tokenRecipients.slice(i, i + BATCH_SIZE);
    const amountsBatch: BigNumber[] = tokenAmounts.slice(i, i + BATCH_SIZE);

    // set recipients
    const txReceipt = await (
      await tokenDistributor.setRecipients(recipientsBatch, amountsBatch)
    ).wait();

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
}

/**
 * Get number of recipients set by checking the number of 'CanClaim' events emitted
 * @param tokenDistributor
 * @returns
 */
export async function getNumberOfRecipientsSet(
  tokenDistributor: TokenDistributor
): Promise<number> {
  const canClaimFilter = tokenDistributor.filters.CanClaim();
  const canClaimEvents = await tokenDistributor.queryFilter(canClaimFilter);
  return canClaimEvents.length;
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
