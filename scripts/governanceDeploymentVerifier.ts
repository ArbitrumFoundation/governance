import { BigNumber, ethers, Signer } from "ethers";
import {
  ArbitrumTimelock,
  ArbitrumTimelock__factory,
  FixedDelegateErc20Wallet,
  FixedDelegateErc20Wallet__factory,
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
    contracts["l1Timelock"],
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
    contracts["l2ArbTreasury"],
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

  await verifyL2Token(contracts["l2Token"], contracts["l2ArbTreasury"], contracts["l1TokenProxy"]);
};

async function verifyL1ContractOwners(
  l1GovernanceFactory: L1GovernanceFactory,
  l1TokenProxy: L1ArbitrumToken,
  l1ProxyAdmin: ProxyAdmin,
  l1Executor: UpgradeExecutor,
  l1Timelock: L1ArbitrumTimelock,
  ethDeployer: Signer
) {
  assertEquals(
    await l1GovernanceFactory.owner(),
    await ethDeployer.getAddress(),
    "EthDeployer should be L1GovernanceFactory's owner"
  );
  assertEquals(
    await getProxyOwner(l1TokenProxy.address, ethDeployer),
    l1ProxyAdmin.address,
    "L1ProxyAdmin should be L1ArbitrumToken's proxy admin"
  );
  assertEquals(
    await getProxyOwner(l1Executor.address, ethDeployer),
    l1ProxyAdmin.address,
    "L1ProxyAdmin should be L1UpgradeExecutor's proxy admin"
  );
  assertEquals(
    await getProxyOwner(l1Timelock.address, ethDeployer),
    l1ProxyAdmin.address,
    "L1ProxyAdmin should be L1ArbitrumTimelock's proxy admin"
  );
  assertEquals(
    await l1ProxyAdmin.owner(),
    l1Executor.address,
    "L1UpgradeExecutor should be L1ProxyAdmin's owner"
  );
}

async function verifyL2ContractOwners(
  l2GovernanceFactory: L2GovernanceFactory,
  l2CoreGovernor: L2ArbitrumGovernor,
  l2ProxyAdmin: ProxyAdmin,
  l2CoreTimelock: ArbitrumTimelock,
  l2Executor: UpgradeExecutor,
  l2Token: L2ArbitrumToken,
  l2TreasuryGoverner: L2ArbitrumGovernor,
  l2ArbTreasury: FixedDelegateErc20Wallet,
  l2TokenDistributor: TokenDistributor,
  arbDeployer: Signer
) {
  assertEquals(
    await l2GovernanceFactory.owner(),
    await arbDeployer.getAddress(),
    "ArbDeployer should be L2GovernanceFactory's owner"
  );
  assertEquals(
    await getProxyOwner(l2CoreGovernor.address, arbDeployer),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be core L2ArbitrumGovernor's proxy admin"
  );
  assertEquals(
    await l2CoreGovernor.owner(),
    l2Executor.address,
    "L2UpgradeExecutor should be core L2ArbitrumGovernor's owner"
  );
  assertEquals(
    await getProxyOwner(l2CoreTimelock.address, arbDeployer),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be L2 core ArbitrumTimelock's proxy admin"
  );
  assertEquals(
    await getProxyOwner(l2Executor.address, arbDeployer),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be L2UpgradeExecutor's proxy admin"
  );
  assertEquals(
    await getProxyOwner(l2Token.address, arbDeployer),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be L2ArbitrumToken's proxy admin"
  );
  assertEquals(
    await l2Token.owner(),
    l2Executor.address,
    "L2UpgradeExecutor should be L2ArbitrumToken's owner"
  );
  assertEquals(
    await getProxyOwner(l2TreasuryGoverner.address, arbDeployer),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be treasury L2ArbitrumGovernor's proxy admin"
  );
  assertEquals(
    await l2TreasuryGoverner.owner(),
    l2Executor.address,
    "L2UpgradeExecutor should be treasury L2ArbitrumGovernor's owner"
  );
  assertEquals(
    await getProxyOwner(l2ArbTreasury.address, arbDeployer),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be arbTreasury's proxy admin"
  );
  assertEquals(
    await l2ArbTreasury.owner(),
    await l2TreasuryGoverner.timelock(),
    "L2TreasuryGoverner's timelock should be arbTreasury's owner"
  );
  assertEquals(
    await l2TokenDistributor.owner(),
    GovernanceConstants.L2_TOKEN_DISTRIBUTOR_OWNER,
    "GovernanceConstants.L2_TOKEN_DISTRIBUTOR_OWNER should be L2 TokenDistributor's owner"
  );
  assertEquals(
    await l2ProxyAdmin.owner(),
    l2Executor.address,
    "L2UpgradeExecutor should be L2ProxyAdmin's owner"
  );
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
    "NovaUpgradeExecutor should be NovaProxyAdmin's owner"
  );
  assertEquals(
    await getProxyOwner(novaUpgradeExecutorProxy.address, novaDeployer),
    novaProxyAdmin.address,
    "NovaProxyAdmin should be NovaUpgradeExecutor's proxy admin"
  );
  assertEquals(
    await getProxyOwner(novaTokenProxy.address, novaDeployer),
    novaProxyAdmin.address,
    "NovaProxyAdmin should be NovaToken's owner"
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
  const cancellerRole = await l2Timelock.CANCELLER_ROLE();
  const executorRole = await l2Timelock.EXECUTOR_ROLE();
  const timelockAdminRole = await l2Timelock.TIMELOCK_ADMIN_ROLE();

  assert(
    await l2Timelock.hasRole(proposerRole, l2CoreGovernor.address),
    "L2 core governor should have proposer role on L2 timelock"
  );
  assert(
    await l2Timelock.hasRole(cancellerRole, l2CoreGovernor.address),
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
    !(await l2Timelock.hasRole(
      cancellerRole,
      GovernanceConstants.L2_7_OF_12_SECURITY_COUNCIL.toString()
    )),
    "L2 7/12 council should not have canceller role on L2 timelock"
  );
  assert(
    await l2Timelock.hasRole(
      cancellerRole,
      GovernanceConstants.L2_9_OF_12_SECURITY_COUNCIL.toString()
    ),
    "L2 9/12 council should have canceller role on L2 timelock"
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

  assertNumbersEquals(
    await l2CoreGovernor.votingDelay(),
    BigNumber.from(GovernanceConstants.L2_VOTING_DELAY),
    "Incorrect voting delay set for L2 core governor"
  );

  assertNumbersEquals(
    await l2CoreGovernor.votingPeriod(),
    BigNumber.from(GovernanceConstants.L2_VOTING_PERIOD),
    "Incorrect voting period set for L2 core governor"
  );

  assertNumbersEquals(
    await l2CoreGovernor.proposalThreshold(),
    BigNumber.from(GovernanceConstants.L2_PROPOSAL_TRESHOLD),
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

  assertNumbersEquals(
    await l2CoreGovernor["quorumNumerator()"](),
    BigNumber.from(GovernanceConstants.L2_CORE_QUORUM_TRESHOLD),
    "Incorrect quorum treshold set for L2 core governor"
  );

  assertNumbersEquals(
    await l2CoreGovernor.lateQuorumVoteExtension(),
    BigNumber.from(GovernanceConstants.L2_MIN_PERIOD_AFTER_QUORUM),
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

/**
 * Verify:
 * - initialization params are correctly set
 * - treasury received correct amount of tokens
 */
async function verifyL2Token(
  l2Token: L2ArbitrumToken,
  arbTreasury: FixedDelegateErc20Wallet,
  l1Token: L1ArbitrumToken
) {
  assertEquals(await l2Token.name(), "Arbitrum", "L2Token name should be Arbitrum");
  assertEquals(await l2Token.symbol(), "ARB", "L2Token symbol should be ARB");
  assertNumbersEquals(
    await l2Token.totalSupply(),
    ethers.utils.parseEther(GovernanceConstants.L2_TOKEN_INITIAL_SUPPLY.toString()),
    "L2Token should have initial supply of " +
      GovernanceConstants.L2_TOKEN_INITIAL_SUPPLY.toString()
  );
  assertNumbersEquals(
    await l2Token.balanceOf(arbTreasury.address),
    BigNumber.from(GovernanceConstants.L2_NUM_OF_TOKENS_FOR_TREASURY),
    "ArbTreasury should have initial balance of " +
      GovernanceConstants.L2_NUM_OF_TOKENS_FOR_TREASURY.toString()
  );
  assertEquals(
    await l2Token.l1Address(),
    l1Token.address,
    "L2Token's l1Token reference should be" + l1Token.address
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
  contracts["l2ArbTreasury"] = FixedDelegateErc20Wallet__factory.connect(
    contractAddresses["l2ArbTreasury"],
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

async function assertNumbersEquals(actual: BigNumber, expected: BigNumber, message: string) {
  if (!actual.eq(expected)) {
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
