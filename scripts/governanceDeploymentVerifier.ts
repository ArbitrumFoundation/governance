import {
  ArbitrumTimelock__factory,
  L1ArbitrumToken__factory,
  L1GovernanceFactory__factory,
  L2ArbitrumGovernor__factory,
  L2ArbitrumToken__factory,
  L2GovernanceFactory__factory,
  ProxyAdmin__factory,
  TokenDistributor__factory,
  UpgradeExecutor__factory,
} from "../typechain-types";
import { L2CustomGatewayToken__factory } from "../typechain-types-imported";
import { getDeployers } from "./providerSetup";

// JSON file which contains all the deployed contract addresses
const DEPLOYED_CONTRACTS_FILE_NAME = "deployedContracts.json";

export const verifyDeployment = async () => {
  await loadContracts();
};

async function loadContracts() {
  const { ethDeployer, arbDeployer, arbInitialSupplyRecipient, novaDeployer } =
    await getDeployers();

  const contractAddresses = require("../" + DEPLOYED_CONTRACTS_FILE_NAME);
  let contracts: { [key: string]: any } = {};

  // load L1 contracts
  contracts["l1GovernanceFactory"] = L1GovernanceFactory__factory.connect(
    contractAddresses["l1GovernanceFactory"],
    ethDeployer
  );
  contracts["l1TokenProxy"] = L1ArbitrumToken__factory.connect(
    contractAddresses["l1TokenProxy"],
    ethDeployer
  );
  contracts["l1executor"] = UpgradeExecutor__factory.connect(
    contractAddresses["l1executor"],
    ethDeployer
  );
  contracts["l1proxyAdmin"] = ProxyAdmin__factory.connect(
    contractAddresses["l1proxyAdmin"],
    ethDeployer
  );

  // load L2 contracts
  contracts["l2token"] = L2ArbitrumToken__factory.connect(
    contractAddresses["l2token"],
    arbDeployer
  );
  contracts["l2upgradeExecutor"] = UpgradeExecutor__factory.connect(
    contractAddresses["l2upgradeExecutor"],
    arbDeployer
  );
  contracts["l2GovernanceFactory"] = L2GovernanceFactory__factory.connect(
    contractAddresses["l2GovernanceFactory"],
    arbDeployer
  );
  contracts["l2coreGoverner"] = L2ArbitrumGovernor__factory.connect(
    contractAddresses["l2coreGoverner"],
    arbDeployer
  );
  contracts["l2coreTimelock"] = ArbitrumTimelock__factory.connect(
    contractAddresses["l2coreTimelock"],
    arbDeployer
  );
  contracts["l2proxyAdmin"] = ProxyAdmin__factory.connect(
    contractAddresses["l2proxyAdmin"],
    arbDeployer
  );
  contracts["l2treasuryGoverner"] = L2ArbitrumGovernor__factory.connect(
    contractAddresses["l2treasuryGoverner"],
    arbDeployer
  );
  contracts["l2treasuryTimelock"] = ArbitrumTimelock__factory.connect(
    contractAddresses["l2treasuryTimelock"],
    arbDeployer
  );
  contracts["l2TokenDistributor"] = TokenDistributor__factory.connect(
    contractAddresses["l2TokenDistributor"],
    arbDeployer
  );

  // load Nova contracts
  contracts["novaProxyAdmin"] = ProxyAdmin__factory.connect(
    contractAddresses["novaProxyAdmin"],
    novaDeployer
  );
  contracts["novaUpgradeExecutorProxy"] = UpgradeExecutor__factory.connect(
    contractAddresses["novaUpgradeExecutorProxy"],
    novaDeployer
  );
  contracts["novaTokenProxy"] = L2CustomGatewayToken__factory.connect(
    contractAddresses["novaTokenProxy"],
    novaDeployer
  );
}

async function assert(condition: Boolean, message: string) {
  if (!condition) {
    throw new Error(message);
  }
}

async function main() {
  console.log("Start verification process...");
  await verifyDeployment();
}

main()
  .then(() => console.log("Done."))
  .catch(console.error);
