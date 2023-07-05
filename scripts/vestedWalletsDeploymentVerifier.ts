import { BigNumber } from "ethers";
import {
  ArbitrumVestingWallet__factory,
  ArbitrumVestingWalletsFactory,
  ArbitrumVestingWalletsFactory__factory,
} from "../typechain-types";
import path from "path";
import fs from "fs";
import dotenv from "dotenv";
import {
  Recipients,
  VestedWallets,
  assertEquals,
  assertNumbersEquals,
  loadVestedRecipients,
} from "./testUtils";
import { JsonRpcProvider, Provider } from "@ethersproject/providers";
import { WalletCreatedEvent } from "../typechain-types/src/ArbitrumVestingWalletFactory.sol/ArbitrumVestingWalletsFactory";

const TOKEN_DEPLOYMENT_TIMESTAMP = 1678968508;

dotenv.config();

async function main() {
  const arbRpc = process.env["ARB_URL"] as string;
  const arbProvider = new JsonRpcProvider(arbRpc);

  const vestedRecipientsLocation = process.env["VESTED_RECIPIENTS_FILE_LOCATION"] as string;
  const vestedRecipientsFileLocation = path.join(__dirname, "..", vestedRecipientsLocation);
  const vestedRecipients = loadVestedRecipients(vestedRecipientsFileLocation);

  const deployedWalletsLocation = process.env["DEPLOYED_WALLETS_FILE_LOCATION"] as string;
  const deployedWalletsFileLocation = path.join(__dirname, "..", deployedWalletsLocation);

  const factoryAddress = getVestedWalletFactoryAddress(deployedWalletsFileLocation);
  const walletFactory = ArbitrumVestingWalletsFactory__factory.connect(factoryAddress, arbProvider);

  await verifyVestedWallets(vestedRecipients, walletFactory, arbProvider);
}

/**
 * Verify:
 * - All vested recipients have a vested wallet
 * - Each vested wallet has the recipient balance of tokens
 */
async function verifyVestedWallets(
  vestedRecipients: VestedWallets,
  vestedWalletFactory: ArbitrumVestingWalletsFactory,
  arbProvider: Provider
) {
  // find all the events emitted by this address
  const filter = vestedWalletFactory.filters["WalletCreated(address,address)"]();

  const walletLogs = (
    await arbProvider.getLogs({
      ...filter,
      fromBlock: 0,
      toBlock: "latest",
    })
  ).map((l) => {
    return vestedWalletFactory.interface.parseLog(l).args as WalletCreatedEvent["args"];
  });

  assertEquals(
    walletLogs.length.toString(),
    Object.values(vestedRecipients)
      .reduce((sum, arr) => sum + arr.length, 0)
      .toString(),
    "Wallets created number not correct"
  );

  for (const vr of Object.keys(vestedRecipients)) {
    const logs = walletLogs.filter((l) => l.beneficiary.toLowerCase() === vr.toLowerCase());

    assertNumbersEquals(
      BigNumber.from(logs.length),
      BigNumber.from(vestedRecipients[vr].length),
      "Too many logs"
    );

    const log = logs[0];

    const vestingWallet = ArbitrumVestingWallet__factory.connect(
      log.vestingWalletAddress,
      arbProvider
    );
    const oneYearInSeconds = 365 * 24 * 60 * 60;

    const start = await vestingWallet.start();
    assertNumbersEquals(
      start,
      BigNumber.from(TOKEN_DEPLOYMENT_TIMESTAMP + oneYearInSeconds),
      "Invalid vesting start time"
    );

    const duration = await vestingWallet.duration();
    assertNumbersEquals(
      duration,
      BigNumber.from(oneYearInSeconds * 3),
      "Invalid vesting duration time"
    );
  }
}

export const getVestedWalletFactoryAddress = (location: string): string => {
  const data = JSON.parse(fs.readFileSync(location).toString());
  return data["vestingWalletFactory"];
};

main().then(() => console.log("Verification complete."));
