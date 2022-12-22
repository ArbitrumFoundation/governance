import { BigNumber, Signer } from "ethers";
import {
  ArbitrumVestingWalletsFactory__factory,
  L2ArbitrumToken__factory,
} from "../typechain-types";
import { WalletCreatedEvent } from "../typechain-types/src/ArbitrumVestingWalletFactory.sol/ArbitrumVestingWalletsFactory";
import fs from "fs";
import { parseEther } from "ethers/lib/utils";

export type VestedRecipients = { readonly [key: string]: BigNumber };

export const loadVestedRecipients = (fileLocation: string): VestedRecipients => {
  const fileContents = fs.readFileSync(fileLocation).toString();
  const jsonFile = JSON.parse(fileContents);
  const addresses = Object.keys(jsonFile);
  const vestedRecipients: { [key: string]: BigNumber } = {};

  for (const addr of addresses) {
    // the token has 18 decimals, like ether, so we can use parseEther
    vestedRecipients[addr.toLowerCase()] = parseEther(jsonFile[addr]);

    if (vestedRecipients[addr.toLowerCase()].lt(parseEther("1"))) {
      throw new Error(
        `Unexpected token count less than 1: ${vestedRecipients[addr.toLowerCase()].toString()}`
      );
    }
  }

  return vestedRecipients;
};

export const deployVestedWallets = async (
  deployer: Signer,
  tokenHolder: Signer,
  tokenAddress: string,
  recipients: VestedRecipients,
  startTimeSeconds: number,
  durationSeconds: number
) => {
  const token = L2ArbitrumToken__factory.connect(tokenAddress, tokenHolder);

  const vestedWalletFactoryFac = new ArbitrumVestingWalletsFactory__factory(deployer);
  const vestedWalletFactory = await vestedWalletFactoryFac.deploy();
  await vestedWalletFactory.deployed();

  const recipientAddresses = Object.keys(recipients);
  const batchSize = 5;

  for (let index = 0; index < recipientAddresses.length; index = index + batchSize) {
    const recipientBatch = recipientAddresses.slice(index, batchSize);

    const walletCreationReceipt = await (
      await vestedWalletFactory.createWallets(startTimeSeconds, durationSeconds, recipientBatch)
    ).wait();

    const walletPairs = walletCreationReceipt.logs
      .map(
        (l) =>
          ArbitrumVestingWalletsFactory__factory.createInterface().parseLog(l)
            .args as WalletCreatedEvent["args"]
      )
      .map((w) => ({
        beneficiary: w.beneficiary,
        wallet: w.vestingWalletAddress,
      }));

    for (const walletPair of walletPairs) {
      const amount = recipients[walletPair.beneficiary.toLowerCase()];

      if (!amount.gt(0)) {
        throw new Error(`Missing amount for ${walletPair.beneficiary}`);
      }

      await (await token.transfer(walletPair.wallet, amount)).wait();
    }
  }

  return vestedWalletFactory;
};
