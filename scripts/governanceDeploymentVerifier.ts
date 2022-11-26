import { ethers, Signer } from "ethers";
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
import * as GovernanceConstants from "./governance.constants";

// JSON file which contains all the deployed contract addresses
const DEPLOYED_CONTRACTS_FILE_NAME = "deployedContracts.json";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

export const verifyDeployment = async () => {
  const { ethDeployer, arbDeployer, novaDeployer } = await getDeployers();

  const contracts = await loadContracts(ethDeployer, arbDeployer, novaDeployer);

  await verifyL1ContractOwners(contracts, ethDeployer);
  await verifyL2ContractOwners(contracts, arbDeployer);
  await verifyNovaContractOwners(contracts, novaDeployer);

  await verifyArbitrumTimelockParams(contracts);
};

async function verifyL1ContractOwners(contracts: { [key: string]: any }, ethDeployer: Signer) {
  assertEquals(
    await contracts["l1GovernanceFactory"].owner(),
    await ethDeployer.getAddress(),
    "Wrong l1GovernanceFactory owner"
  );

  assertEquals(
    await getProxyOwner(contracts["l1TokenProxy"].address, ethDeployer),
    contracts["l1proxyAdmin"].address,
    "Wrong l1GovernanceFactory owner"
  );

  assertEquals(
    await getProxyOwner(contracts["l1executor"].address, ethDeployer),
    contracts["l1proxyAdmin"].address,
    "Wrong l1executor owner"
  );

  assertEquals(
    await contracts["l1proxyAdmin"].owner(),
    contracts["l1executor"].address,
    "Wrong l1proxyAdmin owner"
  );
}

async function verifyL2ContractOwners(contracts: { [key: string]: any }, arbDeployer: Signer) {
  assertEquals(
    await contracts["l2GovernanceFactory"].owner(),
    await arbDeployer.getAddress(),
    "Wrong l2GovernanceFactory owner"
  );

  assertEquals(
    await getProxyOwner(contracts["l2coreGoverner"].address, arbDeployer),
    contracts["l2proxyAdmin"].address,
    "Wrong l2coreGoverner owner"
  );

  assertEquals(
    await getProxyOwner(contracts["l2coreTimelock"].address, arbDeployer),
    contracts["l2proxyAdmin"].address,
    "Wrong l2coreTimelock owner"
  );

  assertEquals(
    await getProxyOwner(contracts["l2executor"].address, arbDeployer),
    contracts["l2proxyAdmin"].address,
    "Wrong l2executor owner"
  );

  assertEquals(
    await getProxyOwner(contracts["l2token"].address, arbDeployer),
    contracts["l2proxyAdmin"].address,
    "Wrong l2token owner"
  );

  assertEquals(
    await getProxyOwner(contracts["l2treasuryGoverner"].address, arbDeployer),
    contracts["l2proxyAdmin"].address,
    "Wrong l2treasuryGoverner owner"
  );

  assertEquals(
    await getProxyOwner(contracts["l2treasuryTimelock"].address, arbDeployer),
    contracts["l2proxyAdmin"].address,
    "Wrong l2treasuryTimelock owner"
  );

  assertEquals(
    await contracts["l2TokenDistributor"].owner(),
    GovernanceConstants.L2_TOKEN_DISTRIBUTOR_OWNER,
    "Wrong l2TokenDistributor owner"
  );

  assertEquals(
    await contracts["l2proxyAdmin"].owner(),
    contracts["l2executor"].address,
    "Wrong l2proxyAdmin owner"
  );
}

async function verifyNovaContractOwners(contracts: { [key: string]: any }, novaDeployer: Signer) {
  assertEquals(
    await contracts["novaProxyAdmin"].owner(),
    contracts["novaUpgradeExecutorProxy"].address,
    "Wrong novaProxyAdmin owner"
  );

  assertEquals(
    await getProxyOwner(contracts["novaUpgradeExecutorProxy"].address, novaDeployer),
    contracts["novaProxyAdmin"].address,
    "Wrong novaUpgradeExecutorProxy owner"
  );

  assertEquals(
    await getProxyOwner(contracts["novaTokenProxy"].address, novaDeployer),
    contracts["novaProxyAdmin"].address,
    "Wrong novaTokenProxy owner"
  );
}

/**
 * Verify:
 * - initialization params are correctly set
 * - roles are correctly assigned
 * @param contracts
 */
async function verifyArbitrumTimelockParams(contracts: { [key: string]: any }) {
  const l2timelock = contracts["l2coreTimelock"];

  //// check initialization params are correctly set
  assertEquals(
    (await l2timelock.getMinDelay()).toString(),
    GovernanceConstants.L2_TIMELOCK_DELAY.toString(),
    "L2 timelock has wrong min delay"
  );

  //// check assigned/revoked roles are correctly set
  const proposerRole = await l2timelock.PROPOSER_ROLE();
  const cancelerRole = await l2timelock.CANCELLER_ROLE();
  const executorRole = await l2timelock.EXECUTOR_ROLE();
  const timelockAdminRole = await l2timelock.TIMELOCK_ADMIN_ROLE();

  assert(
    await l2timelock.hasRole(proposerRole, contracts["l2coreGoverner"].address),
    "L2 core governor should have proposer role on L2 timelock"
  );
  assert(
    await l2timelock.hasRole(cancelerRole, contracts["l2coreGoverner"].address),
    "L2 core governor should have canceller role on L2 timelock"
  );
  assert(
    await l2timelock.hasRole(
      proposerRole,
      GovernanceConstants.L2_7_OF_12_SECURITY_COUNCIL.toString()
    ),
    "L2 7/12 council should have proposer role on L2 timelock"
  );
  assert(
    await l2timelock.hasRole(executorRole, ZERO_ADDRESS),
    "Executor role should be assigned to zero address on L2 timelock"
  );
  assert(
    await l2timelock.hasRole(timelockAdminRole, contracts["l2executor"].address),
    "L2 upgrade executor should have timelock admin role on L2 timelock"
  );
  assert(
    !(await l2timelock.hasRole(timelockAdminRole, l2timelock.address)),
    "L2 timelock should not have timelock admin role on itself"
  );
  assert(
    !(await l2timelock.hasRole(timelockAdminRole, contracts["l2GovernanceFactory"].address)),
    "L2 governance factory should not have timelock admin role on L2 timelock"
  );
}

async function loadContracts(ethDeployer: Signer, arbDeployer: Signer, novaDeployer: Signer) {
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
  contracts["l2executor"] = UpgradeExecutor__factory.connect(
    contractAddresses["l2executor"],
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

  return contracts;
}

async function getProxyOwner(contractAddress: string, signer: Signer) {
  // gets address in format like 0x000000000000000000000000a898b332e65d0cc9cb538495ff145983806d8453
  const ownerStorageValue = await signer.provider?.getStorageAt(
    contractAddress,
    "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
  );

  if (!ownerStorageValue) {
    return "";
  }

  // remove execess bytes -> 0xa898b332e65d0cc9cb538495ff145983806d8453
  const formatAddress = ownerStorageValue.substring(0, 2) + ownerStorageValue.substring(26);

  // return address as checksum address -> 0xA898b332e65D0cc9CB538495FF145983806D8453
  return ethers.utils.getAddress(formatAddress);
}

async function assertEquals(actual: string, expected: string, message: string) {
  if (actual != expected) {
    console.error("Actual: ", actual);
    console.error("Expected: ", expected);
    throw new Error(message);
  }
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
