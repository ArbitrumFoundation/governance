import { ethers, Signer } from "ethers";
import {
  ArbitrumTimelock,
  ArbitrumTimelock__factory,
  L1ArbitrumTimelock,
  L1ArbitrumToken,
  L1ArbitrumToken__factory,
  L1GovernanceFactory,
  L1GovernanceFactory__factory,
  L2ArbitrumGovernor,
  L2ArbitrumGovernor__factory,
  L2ArbitrumToken,
  L2ArbitrumToken__factory,
  L2GovernanceFactory,
  L2GovernanceFactory__factory,
  ProxyAdmin,
  ProxyAdmin__factory,
  TokenDistributor,
  TokenDistributor__factory,
  UpgradeExecutor,
  UpgradeExecutor__factory,
} from "../typechain-types";
import { L2CustomGatewayToken, L2CustomGatewayToken__factory } from "../typechain-types-imported";
import { getDeployers } from "./providerSetup";
import * as GovernanceConstants from "./governance.constants";
import { Address } from "@arbitrum/sdk";

// JSON file which contains all the deployed contract addresses
const DEPLOYED_CONTRACTS_FILE_NAME = "deployedContracts.json";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

export const verifyDeployment = async () => {
  const { ethDeployer, arbDeployer, novaDeployer } = await getDeployers();

  const contracts = await loadContracts(ethDeployer, arbDeployer, novaDeployer);

  await verifyL1ContractOwners(
    contracts["l1GovernanceFactory"],
    contracts["l1TokenProxy"],
    contracts["l1ProxyAdmin"],
    contracts["l1Executor"],
    ethDeployer
  );
  await verifyL2ContractOwners(
    contracts["l2GovernanceFactory"],
    contracts["l2CoreGoverner"],
    contracts["l2ProxyAdmin"],
    contracts["l2CoreTimelock"],
    contracts["l2Executor"],
    contracts["l2Token"],
    contracts["l2TreasuryGoverner"],
    contracts["l2TreasuryTimelock"],
    contracts["l2TokenDistributor"],
    arbDeployer
  );
  await verifyNovaContractOwners(
    contracts["novaProxyAdmin"],
    contracts["novaUpgradeExecutorProxy"],
    contracts["novaTokenProxy"],
    novaDeployer
  );

  await verifyArbitrumTimelockParams(
    contracts["l2CoreTimelock"],
    contracts["l2CoreGoverner"],
    contracts["l2Executor"],
    contracts["l2GovernanceFactory"]
  );
  await verifyL2GovernanceFactory(contracts["l2GovernanceFactory"]);
  await verifyL2CoreGovernor(
    contracts["l2CoreGoverner"],
    contracts["l2Token"],
    contracts["l2CoreTimelock"]
  );
  await verifyL2UpgradeExecutor(contracts["l2Executor"], contracts["l1Timelock"]);
};

async function verifyL1ContractOwners(
  l1GovernanceFactory: L1GovernanceFactory,
  l1TokenProxy: L1ArbitrumToken,
  l1ProxyAdmin: ProxyAdmin,
  l1Executor: UpgradeExecutor,
  ethDeployer: Signer
) {
  assertEquals(
    await l1GovernanceFactory.owner(),
    await ethDeployer.getAddress(),
    "Wrong l1GovernanceFactory owner"
  );

  assertEquals(
    await getProxyOwner(l1TokenProxy.address, ethDeployer),
    l1ProxyAdmin.address,
    "Wrong l1GovernanceFactory owner"
  );

  assertEquals(
    await getProxyOwner(l1Executor.address, ethDeployer),
    l1ProxyAdmin.address,
    "Wrong l1Executor owner"
  );

  assertEquals(
    await getProxyOwner(l1Executor.address, ethDeployer),
    l1ProxyAdmin.address,
    "Wrong l1Timelock owner"
  );

  assertEquals(await l1ProxyAdmin.owner(), l1Executor.address, "Wrong l1ProxyAdmin owner");
}

async function verifyL2ContractOwners(
  l2GovernanceFactory: L2GovernanceFactory,
  l2CoreGovernor: L2ArbitrumGovernor,
  l2ProxyAdmin: ProxyAdmin,
  l2CoreTimelock: ArbitrumTimelock,
  l2Executor: UpgradeExecutor,
  l2Token: L2ArbitrumToken,
  l2TreasuryGoverner: L2ArbitrumGovernor,
  l2TreasuryTimelock: ArbitrumTimelock,
  l2TokenDistributor: TokenDistributor,
  arbDeployer: Signer
) {
  assertEquals(
    await l2GovernanceFactory.owner(),
    await arbDeployer.getAddress(),
    "Wrong l2GovernanceFactory owner"
  );
  assertEquals(
    await getProxyOwner(l2CoreGovernor.address, arbDeployer),
    l2ProxyAdmin.address,
    "Wrong l2CoreGoverner owner"
  );
  assertEquals(
    await getProxyOwner(l2CoreTimelock.address, arbDeployer),
    l2ProxyAdmin.address,
    "Wrong l2CoreTimelock owner"
  );
  assertEquals(
    await getProxyOwner(l2Executor.address, arbDeployer),
    l2ProxyAdmin.address,
    "Wrong l2Executor owner"
  );
  assertEquals(
    await getProxyOwner(l2Token.address, arbDeployer),
    l2ProxyAdmin.address,
    "Wrong l2Token owner"
  );
  assertEquals(
    await getProxyOwner(l2TreasuryGoverner.address, arbDeployer),
    l2ProxyAdmin.address,
    "Wrong l2TreasuryGoverner owner"
  );
  assertEquals(
    await getProxyOwner(l2TreasuryTimelock.address, arbDeployer),
    l2ProxyAdmin.address,
    "Wrong l2TreasuryTimelock owner"
  );
  assertEquals(
    await l2TokenDistributor.owner(),
    GovernanceConstants.L2_TOKEN_DISTRIBUTOR_OWNER,
    "Wrong l2TokenDistributor owner"
  );
  assertEquals(await l2ProxyAdmin.owner(), l2Executor.address, "Wrong l2ProxyAdmin owner");
}

async function verifyNovaContractOwners(
  novaProxyAdmin: ProxyAdmin,
  novaUpgradeExecutorProxy: UpgradeExecutor,
  novaTokenProxy: L2CustomGatewayToken,
  novaDeployer: Signer
) {
  assertEquals(
    await novaProxyAdmin.owner(),
    novaUpgradeExecutorProxy.address,
    "Wrong novaProxyAdmin owner"
  );
  assertEquals(
    await getProxyOwner(novaUpgradeExecutorProxy.address, novaDeployer),
    novaProxyAdmin.address,
    "Wrong novaUpgradeExecutorProxy owner"
  );
  assertEquals(
    await getProxyOwner(novaTokenProxy.address, novaDeployer),
    novaProxyAdmin.address,
    "Wrong novaTokenProxy owner"
  );
}

/**
 * Verify:
 * - factory has completed job
 */
async function verifyL2GovernanceFactory(l2govFactory: L2GovernanceFactory) {
  // check factory has completed job
  // 2 == Step.Complete
  assertEquals(
    (await l2govFactory.step()).toString(),
    "2",
    "L2 governance factory should be in 'Complete'(2) step"
  );
}

/**
 * Verify:
 * - initialization params are correctly set
 * - roles are correctly assigned
 */
async function verifyArbitrumTimelockParams(
  l2Timelock: ArbitrumTimelock,
  l2CoreGovernor: L2ArbitrumGovernor,
  l2Executor: UpgradeExecutor,
  l2GovernanceFactory: L2GovernanceFactory
) {
  //// check initialization params are correctly set
  assertEquals(
    (await l2Timelock.getMinDelay()).toString(),
    GovernanceConstants.L2_TIMELOCK_DELAY.toString(),
    "L2 timelock has wrong min delay"
  );

  //// check assigned/revoked roles are correctly set
  const proposerRole = await l2Timelock.PROPOSER_ROLE();
  const cancelerRole = await l2Timelock.CANCELLER_ROLE();
  const executorRole = await l2Timelock.EXECUTOR_ROLE();
  const timelockAdminRole = await l2Timelock.TIMELOCK_ADMIN_ROLE();

  assert(
    await l2Timelock.hasRole(proposerRole, l2CoreGovernor.address),
    "L2 core governor should have proposer role on L2 timelock"
  );
  assert(
    await l2Timelock.hasRole(cancelerRole, l2CoreGovernor.address),
    "L2 core governor should have canceller role on L2 timelock"
  );
  assert(
    await l2Timelock.hasRole(
      proposerRole,
      GovernanceConstants.L2_7_OF_12_SECURITY_COUNCIL.toString()
    ),
    "L2 7/12 council should have proposer role on L2 timelock"
  );
  assert(
    await l2Timelock.hasRole(executorRole, ZERO_ADDRESS),
    "Executor role should be assigned to zero address on L2 timelock"
  );
  assert(
    await l2Timelock.hasRole(timelockAdminRole, l2Executor.address),
    "L2 upgrade executor should have timelock admin role on L2 timelock"
  );
  assert(
    !(await l2Timelock.hasRole(timelockAdminRole, l2Timelock.address)),
    "L2 timelock should not have timelock admin role on itself"
  );
  assert(
    !(await l2Timelock.hasRole(timelockAdminRole, l2GovernanceFactory.address)),
    "L2 governance factory should not have timelock admin role on L2 timelock"
  );
}

/**
 * Verify:
 * - initialization params are correctly set
 */
async function verifyL2CoreGovernor(
  l2CoreGovernor: L2ArbitrumGovernor,
  l2Token: L2ArbitrumToken,
  l2Timelock: ArbitrumTimelock
) {
  //// check initialization params are correctly set

  assertEquals(
    await l2CoreGovernor.name(),
    "L2ArbitrumGovernor",
    "Incorrect L2 core governor's name"
  );

  assertEquals(
    (await l2CoreGovernor.votingDelay()).toString(),
    GovernanceConstants.L2_VOTING_DELAY.toString(),
    "Incorrect voting delay set for L2 core governor"
  );

  assertEquals(
    (await l2CoreGovernor.votingPeriod()).toString(),
    GovernanceConstants.L2_VOTING_PERIOD.toString(),
    "Incorrect voting period set for L2 core governor"
  );

  assertEquals(
    (await l2CoreGovernor.proposalThreshold()).toString(),
    GovernanceConstants.L2_PROPOSAL_TRESHOLD.toString(),
    "Incorrect proposal threshold set for L2 core governor"
  );

  assertEquals(
    await l2CoreGovernor.token(),
    l2Token.address,
    "Incorrect token set for L2 core governor"
  );

  assertEquals(
    await l2CoreGovernor.timelock(),
    l2Timelock.address,
    "Incorrect timelock set for L2 core governor"
  );

  assertEquals(
    (await l2CoreGovernor["quorumNumerator()"]()).toString(),
    GovernanceConstants.L2_CORE_QUORUM_TRESHOLD.toString(),
    "Incorrect quorum treshold set for L2 core governor"
  );

  assertEquals(
    (await l2CoreGovernor.lateQuorumVoteExtension()).toString(),
    GovernanceConstants.L2_MIN_PERIOD_AFTER_QUORUM.toString(),
    "Incorrect min period after quorum set for L2 core governor"
  );
}

/**
 * Verify:
 * - roles are correctly assigned
 */
async function verifyL2UpgradeExecutor(
  l2Executor: UpgradeExecutor,
  l1Timelock: L1ArbitrumTimelock
) {
  //// check assigned/revoked roles are correctly set
  const adminRole = await l2Executor.ADMIN_ROLE();
  const executorRole = await l2Executor.EXECUTOR_ROLE();

  assert(
    await l2Executor.hasRole(adminRole, l2Executor.address),
    "L2 upgrade executor should have admin role on itself"
  );

  const l1TimelockAddressAliased = new Address(l1Timelock.address).applyAlias().value;
  assert(
    await l2Executor.hasRole(executorRole, l1TimelockAddressAliased),
    "L1 timelock (aliased) should have executor role on L2 upgrade executor"
  );
  assert(
    await l2Executor.hasRole(executorRole, GovernanceConstants.L2_9_OF_12_SECURITY_COUNCIL),
    "L2 9/12 council should have executor role on L2 upgrade executor"
  );
}

async function loadContracts(
  ethDeployer: Signer,
  arbDeployer: Signer,
  novaDeployer: Signer
): Promise<{ [key: string]: any }> {
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
  contracts["l1Executor"] = UpgradeExecutor__factory.connect(
    contractAddresses["l1Executor"],
    ethDeployer
  );
  contracts["l1Timelock"] = UpgradeExecutor__factory.connect(
    contractAddresses["l1Timelock"],
    ethDeployer
  );
  contracts["l1ProxyAdmin"] = ProxyAdmin__factory.connect(
    contractAddresses["l1ProxyAdmin"],
    ethDeployer
  );

  // load L2 contracts
  contracts["l2Token"] = L2ArbitrumToken__factory.connect(
    contractAddresses["l2Token"],
    arbDeployer
  );
  contracts["l2Executor"] = UpgradeExecutor__factory.connect(
    contractAddresses["l2Executor"],
    arbDeployer
  );
  contracts["l2GovernanceFactory"] = L2GovernanceFactory__factory.connect(
    contractAddresses["l2GovernanceFactory"],
    arbDeployer
  );
  contracts["l2CoreGoverner"] = L2ArbitrumGovernor__factory.connect(
    contractAddresses["l2CoreGoverner"],
    arbDeployer
  );
  contracts["l2CoreTimelock"] = ArbitrumTimelock__factory.connect(
    contractAddresses["l2CoreTimelock"],
    arbDeployer
  );
  contracts["l2ProxyAdmin"] = ProxyAdmin__factory.connect(
    contractAddresses["l2ProxyAdmin"],
    arbDeployer
  );
  contracts["l2TreasuryGoverner"] = L2ArbitrumGovernor__factory.connect(
    contractAddresses["l2TreasuryGoverner"],
    arbDeployer
  );
  contracts["l2TreasuryTimelock"] = ArbitrumTimelock__factory.connect(
    contractAddresses["l2TreasuryTimelock"],
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
