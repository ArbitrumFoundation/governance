import { Signer, Wallet } from "ethers";
import { ArbitrumVestingWalletsFactory__factory } from "../typechain-types";
import {
  ArbitrumVestingWalletsFactory,
  WalletCreatedEvent,
} from "../typechain-types/src/ArbitrumVestingWalletFactory.sol/ArbitrumVestingWalletsFactory";
import { Recipients, VestedWallets, loadRecipients, loadVestedRecipients } from "./testUtils";
import dotenv from "dotenv";
import path from "path";
import fs from "fs";
import { JsonRpcProvider } from "@ethersproject/providers";

dotenv.config();

const TOKEN_DEPLOYMENT_TIMESTAMP = 1678968508;
const ONE_YEAR_IN_SECONDS = 365 * 24 * 60 * 60;

interface DeploymentData {
  vestingWalletFactory: string;
  beneficiaries: BeneficiaryData[];
}

interface BeneficiaryData {
  beneficiary: string;
  walletAddresses: string[];
}

const deployVestedWallets = async (
  deployedWalletsFileLocation: string,
  deployer: Signer,
  recipients: VestedWallets,
  startTimeSeconds: number,
  durationSeconds: number
) => {
  const data = loadDeployedWallets(deployedWalletsFileLocation);

  let vestedWalletFactory: ArbitrumVestingWalletsFactory;
  if (data.vestingWalletFactory === "" || data.vestingWalletFactory === undefined) {
    // deploy factory
    console.log("Deploying factory...");
    const vestedWalletFactoryFac = new ArbitrumVestingWalletsFactory__factory(deployer);
    vestedWalletFactory = await vestedWalletFactoryFac.deploy();
    await vestedWalletFactory.deployed();
    data.vestingWalletFactory = vestedWalletFactory.address;
    // store factory address
    updateDeployedWallets(deployedWalletsFileLocation, data);
  } else {
    // load factory
    vestedWalletFactory = ArbitrumVestingWalletsFactory__factory.connect(
      data.vestingWalletFactory,
      deployer
    );
  }

  // make a list of beneficiary addresses where address can occur multiple times
  const recipientAddresses = Object.keys(recipients)
    .map((key) => Array(recipients[key].length).fill(key))
    .flat();
  // sum up number of already deployed wallets
  const startIndex = data.beneficiaries.reduce((sum, obj) => sum + obj.walletAddresses.length, 0);
  const batchSize = 5;

  /// deploy wallets in batches of 5
  for (let index = startIndex; index < recipientAddresses.length; index = index + batchSize) {
    const recipientBatch = recipientAddresses.slice(index, index + batchSize);

    console.log("Deploying wallets [", index, ",", index + batchSize, "]");
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
      const beneficiaryData = data.beneficiaries.find(
        (b) => b.beneficiary == walletPair.beneficiary
      );

      if (beneficiaryData !== undefined) {
        // add new wallet for existing beneficiary
        beneficiaryData.walletAddresses.push(walletPair.wallet);
      } else {
        // this is a 1st wallet for this beneficiary
        data.beneficiaries.push({
          beneficiary: walletPair.beneficiary,
          walletAddresses: [walletPair.wallet],
        });
      }
    }
    updateDeployedWallets(deployedWalletsFileLocation, data);
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
  const vestedRecipients = loadVestedRecipients(vestedRecipientsFileLocation);

  const arbDeployer = new Wallet(arbKey, new JsonRpcProvider(arbRpc));

  await deployVestedWallets(
    deployedWalletsFileLocation,
    arbDeployer,
    vestedRecipients,
    // start vesting 1 year after token generation
    TOKEN_DEPLOYMENT_TIMESTAMP + ONE_YEAR_IN_SECONDS,
    // vesting lasts for 3 years
    ONE_YEAR_IN_SECONDS * 3
  );

  console.log("Wallets deployed, deployment data here:", deployedWalletsFileLocation);
}

const loadDeployedWallets = (location: string): DeploymentData => {
  if (!fs.existsSync(location)) return { vestingWalletFactory: "", beneficiaries: [] };
  return JSON.parse(fs.readFileSync(location).toString()) as DeploymentData;
};

const updateDeployedWallets = (location: string, data: DeploymentData) => {
  fs.writeFileSync(location, JSON.stringify(data, null, 2));
};

main().then(() => console.log("Done."));
