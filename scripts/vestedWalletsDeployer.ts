import { Signer } from "ethers";
import {
  ArbitrumVestingWalletsFactory__factory,
  L2ArbitrumToken__factory,
} from "../typechain-types";
import { WalletCreatedEvent } from "../typechain-types/src/ArbitrumVestingWalletFactory.sol/ArbitrumVestingWalletsFactory";
import { Recipients, loadRecipients } from "./testUtils";
import dotenv from "dotenv";
import path from "path";
import fs from "fs";

dotenv.config();

export const deployVestedWallets = async (
  deployer: Signer,
  tokenHolder: Signer,
  tokenAddress: string,
  recipients: Recipients,
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

// async function deployAndTransferVestedWallets(
//   arbDeployer: Signer,
//   arbInitialSupplyRecipient: Signer,
//   l2TokenAddress: string,
//   vestedRecipients: Recipients,
//   config: {
//     L2_CLAIM_PERIOD_START: number;
//   }
// ) {
//   const oneYearInSeconds = 365 * 24 * 60 * 60;

//   if (!deployedContracts.vestedWalletFactory) {
//     // we dont currently have full error handling for errors thrown during
//     // vested wallet deployment, for now just throw an error and require
//     // manual intervention if an error occurs in here
//     if (deployedContracts.vestedWalletInProgress) {
//       throw new Error(
//         "Vested wallet deployment started but a failure occurred, manual intervention required"
//       );
//     }
//     deployedContracts.vestedWalletInProgress = true;

//     const vestedWalletFactory = await deployVestedWallets(
//       arbDeployer,
//       arbInitialSupplyRecipient,
//       l2TokenAddress,
//       vestedRecipients,
//       // start vesting in 1 years time
//       config.L2_CLAIM_PERIOD_START + oneYearInSeconds,
//       // vesting lasts for 3 years
//       oneYearInSeconds * 3
//     );
//     deployedContracts.vestedWalletInProgress = undefined;
//     deployedContracts.vestedWalletFactory = vestedWalletFactory.address;
//   }
// }

async function main() {
  console.log("Start vested wallets deployment process...");

  const vestedRecipientsLocation = process.env["VESTED_RECIPIENTS_FILE_LOCATION"] as string;
  const deployedWalletsLocation = process.env["DEPLOYED_WALLETS_FILE_LOCATION"] as string;

  if (vestedRecipientsLocation === undefined || deployedWalletsLocation === undefined) {
    throw new Error(
      "VESTED_RECIPIENTS_FILE_LOCATION and DEPLOYED_WALLETS_FILE_LOCATION have to be defined in env vars"
    );
  }

  const vestedRecipientsFileLocation = path.join(__dirname, "..", vestedRecipientsLocation);
  const beneficiaries = loadRecipients(vestedRecipientsFileLocation);

  // const deployedWallets = loadDeployedWallets(deployedWalletsLocation);
  // console.log(`Cache: ${JSON.stringify(deployedContracts, null, 2)}`);
  // try {
  //   await deployVestedWallets();
  // } finally {
  //   // write addresses of deployed contracts even when exception is thrown
  //   console.log("Write deployed contract addresses to deployedContracts.json");
  //   updateDeployedWallets(deployedWallets);
  // }
  // console.log("Allocation finished!");
}

process.on("SIGINT", function () {
  console.log("Detected interrupt");
  console.log("Write deployed wallet addresses to deployedWallets.json");
  process.exit();
});

// const loadDeployedWallets = (location: string): string[] => {
//   if (!fs.existsSync(location)) return [];
//   return JSON.parse(
//     fs.readFileSync(envVars.deployedContractsLocation).toString()
//   ) as DeployProgressCache;
// };

// const updateDeployedWallets = (cache: DeployProgressCache) => {
//   fs.writeFileSync(envVars.deployedWalletsLocation, JSON.stringify(cache, null, 2));
// };

main().then(() => console.log("Done."));
