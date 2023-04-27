import { Signer, Wallet } from "ethers";
import { ArbitrumVestingWalletsFactory__factory } from "../typechain-types";
import { WalletCreatedEvent } from "../typechain-types/src/ArbitrumVestingWalletFactory.sol/ArbitrumVestingWalletsFactory";
import { Recipients, loadRecipients } from "./testUtils";
import dotenv from "dotenv";
import path from "path";
import fs from "fs";
import { JsonRpcProvider } from "@ethersproject/providers";

dotenv.config();

const TOKEN_DEPLOYMENT_TIMESTAMP = 1678968508;
const ONE_YEAR_IN_SECONDS = 365 * 24 * 60 * 60;

interface VestedWallet {
  beneficiary: string;
  walletAddress: string;
}

interface DeploymentData {
  vestingWalletFactory: string;
  wallets: VestedWallet[];
}

export const deployVestedWallets = async (
  deployedWalletsFileLocation: string,
  deployer: Signer,
  recipients: Recipients,
  startTimeSeconds: number,
  durationSeconds: number
) => {
  let data: DeploymentData = { vestingWalletFactory: "", wallets: [] };

  // deploy factory
  const vestedWalletFactoryFac = new ArbitrumVestingWalletsFactory__factory(deployer);
  const vestedWalletFactory = await vestedWalletFactoryFac.deploy();
  await vestedWalletFactory.deployed();
  data.vestingWalletFactory = vestedWalletFactory.address;
  // store factory address
  updateDeployedWallets(deployedWalletsFileLocation, data);

  /// deploy wallets in batches of 5
  const recipientAddresses = Object.keys(recipients);
  const batchSize = 5;

  for (let index = 0; index < recipientAddresses.length; index = index + batchSize) {
    const recipientBatch = recipientAddresses.slice(index, index + batchSize);

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

    // store wallet addresses
    for (const walletPair of walletPairs) {
      data.wallets.push({ beneficiary: walletPair.beneficiary, walletAddress: walletPair.wallet });
      updateDeployedWallets(deployedWalletsFileLocation, data);
    }
  }

  return vestedWalletFactory;
};

async function main() {
  console.log("Start vested wallets deployment process...");

  /// get env vars
  const arbKey = process.env["ARB_KEY"] as string;
  const arbRpc = process.env["ARB_URL"] as string;
  const vestedRecipientsLocation = process.env["VESTED_RECIPIENTS_FILE_LOCATION"] as string;
  const deployedWalletsLocation = process.env["DEPLOYED_WALLETS_FILE_LOCATION"] as string;
  if (
    arbKey === undefined ||
    arbRpc === undefined ||
    vestedRecipientsLocation === undefined ||
    deployedWalletsLocation === undefined
  ) {
    throw new Error(
      "Following env vars have to be defined: ARB_KEY, ARB_URL, VESTED_RECIPIENTS_FILE_LOCATION and DEPLOYED_WALLETS_FILE_LOCATION"
    );
  }

  const deployedWalletsFileLocation = path.join(__dirname, "..", deployedWalletsLocation);
  const vestedRecipientsFileLocation = path.join(__dirname, "..", vestedRecipientsLocation);
  const vestedRecipients = loadRecipients(vestedRecipientsFileLocation);
  const arbDeployer = new Wallet(arbKey, new JsonRpcProvider(arbRpc));

  await deployVestedWallets(
    deployedWalletsFileLocation,
    arbDeployer,
    vestedRecipients,
    // start vesting in 1 years time
    TOKEN_DEPLOYMENT_TIMESTAMP + ONE_YEAR_IN_SECONDS,
    // vesting lasts for 3 years
    ONE_YEAR_IN_SECONDS * 3
  );

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

const updateDeployedWallets = (location: string, data: DeploymentData) => {
  fs.writeFileSync(location, JSON.stringify(data, null, 2));
};

main().then(() => console.log("Done."));
