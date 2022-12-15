import { JsonRpcProvider } from "@ethersproject/providers";
import { BigNumber, Signer } from "ethers";
import {
  ArbitrumVestingWalletsFactory__factory,
  ArbitrumVestingWallet__factory,
  L2ArbitrumToken__factory,
} from "../typechain-types";
import { WalletCreatedEvent } from "../typechain-types/src/ArbitrumVestingWalletFactory.sol/ArbitrumVestingWalletsFactory";
import fs from "fs";

type VestedRecipients = { readonly [key: string]: BigNumber };

export class VestedWalletDeployer {
  public constructor(
    private readonly deployer: Signer,
    private readonly tokenHolder: Signer,
    private readonly tokenAddress: string,
    private readonly recipients: VestedRecipients,
    private readonly startTimeSeconds: number,
    private readonly durationSeconds: number,
    private readonly vestedWalletFactoryAddress: string
  ) {}

  public static loadRecipients(fileLocation: string): VestedRecipients {
    const fileContents = fs.readFileSync(fileLocation).toString();

    const jsonFile = JSON.parse(fileContents);

    const addresses = Object.keys(jsonFile);

    const vestedRecipients: { [key: string]: BigNumber } = {};
    for (const addr of addresses) {
      vestedRecipients[addr.toLowerCase()] = BigNumber.from(jsonFile[addr]);
    }
    return vestedRecipients;
  }

  public async deploy() {
    const token = L2ArbitrumToken__factory.connect(
      this.tokenAddress,
      this.tokenHolder
    );
    const vestedWalletFactory = ArbitrumVestingWalletsFactory__factory.connect(
      this.vestedWalletFactoryAddress,
      this.deployer
    );

    const recipientAddresses = Object.keys(this.recipients);
    const batchSize = 10;

    for (let index = 0; index < recipientAddresses.length; index + batchSize) {
      const recipientBatch = recipientAddresses.slice(index, batchSize);

      const walletCreationReceipt = await (
        await vestedWalletFactory.createWallets(
          this.startTimeSeconds,
          this.durationSeconds,
          recipientBatch
        )
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
        const amount = this.recipients[walletPair.beneficiary.toLowerCase()];

        if (!amount.gt(0)) {
          throw new Error(`Missing amount for ${walletPair.beneficiary}`);
        }

        await (await token.transfer(walletPair.wallet, amount)).wait();
      }
    }
  }
}
