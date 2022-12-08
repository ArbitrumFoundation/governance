import { BigNumber, ethers } from "ethers";
import {
  ArbitrumTimelock,
  ArbitrumTimelock__factory,
  FixedDelegateErc20Wallet,
  FixedDelegateErc20Wallet__factory,
  IInbox__factory,
  IVotesUpgradeable__factory,
  L1ArbitrumTimelock,
  L1ArbitrumTimelock__factory,
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
import {
  L1ForceOnlyReverseCustomGateway,
  L1ForceOnlyReverseCustomGateway__factory,
  L2CustomGatewayToken,
  L2CustomGatewayToken__factory,
  L2ReverseCustomGateway,
  L2ReverseCustomGateway__factory,
} from "../typechain-types-imported";
import { getDeployerAddresses, getProviders } from "./providerSetup";
import * as GovernanceConstants from "./governance.constants";
import { Address } from "@arbitrum/sdk";
import { parseEther } from "ethers/lib/utils";
import { L1CustomGateway__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L1CustomGateway__factory";
import { L1GatewayRouter__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L1GatewayRouter__factory";
import { Provider } from "@ethersproject/providers";

// JSON file which contains all the deployed contract addresses
const DEPLOYED_CONTRACTS_FILE_NAME = "deployedContracts.json";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

/**
 * Main function that verifies governance deployment was successful.
 */
export const verifyDeployment = async () => {
  const { ethProvider, arbProvider, novaProvider } = await getProviders();
  const { ethDeployerAddress, arbDeployerAddress } = await getDeployerAddresses();

  const contracts = await loadContracts(ethProvider, arbProvider, novaProvider);

  //// L1 contracts

  console.log("Verify L1 contracts are properly deployed");
  await verifyL1GovernanceFactory(contracts["l1GovernanceFactory"], ethDeployerAddress);
  await verifyL1Token(
    contracts["l1TokenProxy"],
    contracts["l1ProxyAdmin"],
    contracts["l1ReverseCustomGatewayProxy"],
    contracts["l2Token"],
    contracts["novaTokenProxy"],
    ethProvider
  );
  await verifyL1UpgradeExecutor(
    contracts["l1Executor"],
    contracts["l1Timelock"],
    contracts["l1ProxyAdmin"],
    ethProvider
  );
  await verifyL1Timelock(
    contracts["l1Timelock"],
    contracts["l1Executor"],
    contracts["l1GovernanceFactory"],
    contracts["l2CoreTimelock"],
    contracts["l1ProxyAdmin"],
    ethProvider
  );
  await verifyL1ProxyAdmin(contracts["l1ProxyAdmin"], contracts["l1Executor"]);

  await verifyL1ReverseGateway(
    contracts["l1ReverseCustomGatewayProxy"],
    contracts["l2ReverseCustomGatewayProxy"],
    contracts["l1ProxyAdmin"],
    ethProvider,
    ethDeployerAddress
  );

  //// L2 contracts

  console.log("Verify L2 contracts are properly deployed");
  await verifyArbitrumTimelock(
    contracts["l2CoreTimelock"],
    contracts["l2CoreGoverner"],
    contracts["l2Executor"],
    contracts["l2GovernanceFactory"],
    contracts["l2ProxyAdmin"],
    arbProvider
  );
  await verifyL2GovernanceFactory(contracts["l2GovernanceFactory"], arbDeployerAddress);
  await verifyL2CoreGovernor(
    contracts["l2CoreGoverner"],
    contracts["l2Token"],
    contracts["l2CoreTimelock"],
    contracts["l2Executor"],
    contracts["l2ProxyAdmin"],
    arbProvider
  );
  await verifyL2UpgradeExecutor(
    contracts["l2Executor"],
    contracts["l1Timelock"],
    contracts["l2ProxyAdmin"],
    arbProvider
  );
  await verifyL2Token(
    contracts["l2Token"],
    contracts["l2ArbTreasury"],
    contracts["l1TokenProxy"],
    contracts["l2Executor"],
    contracts["l2ProxyAdmin"],
    contracts["l2TokenDistributor"],
    arbProvider
  );
  await verifyL2TreasuryGovernor(
    contracts["l2TreasuryGoverner"],
    contracts["l2Token"],
    contracts["l2Executor"],
    contracts["l2ProxyAdmin"],
    arbProvider
  );

  const l2TreasuryTimelock = ArbitrumTimelock__factory.connect(
    await contracts["l2TreasuryGoverner"].timelock(),
    arbProvider
  );
  await verifyL2TreasuryTimelock(
    l2TreasuryTimelock,
    contracts["l2TreasuryGoverner"],
    contracts["l2Executor"],
    contracts["l2GovernanceFactory"],
    contracts["l2ProxyAdmin"],
    arbProvider
  );
  await verifyL2ArbTreasury(
    contracts["l2ArbTreasury"],
    contracts["l2Token"],
    contracts["l2TreasuryGoverner"],
    contracts["l2ProxyAdmin"],
    arbProvider
  );
  await verifyL2TokenDistributor(
    contracts["l2TokenDistributor"],
    contracts["l2Token"],
    contracts["l2Executor"],
    contracts["l2CoreGoverner"],
    arbProvider
  );
  await verifyL2ProxyAdmin(contracts["l2ProxyAdmin"], contracts["l2Executor"]);
  await verifyL2ReverseGateway(
    contracts["l2ReverseCustomGatewayProxy"],
    contracts["l1ReverseCustomGatewayProxy"],
    contracts["l2ProxyAdmin"],
    arbProvider
  );

  //// Nova contracts

  console.log("Verify Nova contracts are properly deployed");
  await verifyNovaUpgradeExecutor(
    contracts["novaUpgradeExecutorProxy"],
    contracts["l1Timelock"],
    contracts["novaProxyAdmin"],
    novaProvider
  );
  await verifyNovaToken(
    contracts["novaTokenProxy"],
    contracts["l1TokenProxy"],
    contracts["novaProxyAdmin"],
    novaProvider
  );
  await verifyNovaProxyAdmin(contracts["novaProxyAdmin"], contracts["novaUpgradeExecutorProxy"]);
};

/**
 * Verify:
 * - factory ownership
 */
async function verifyL1GovernanceFactory(
  l1GovernanceFactory: L1GovernanceFactory,
  ethDeployerAddress: string
) {
  assertEquals(
    await l1GovernanceFactory.owner(),
    ethDeployerAddress,
    "EthDeployer should be L1GovernanceFactory's owner"
  );
}

/**
 * Verify:
 * - proxy admin is correct
 * - initialization params are correctly set
 */
async function verifyL1Token(
  l1Token: L1ArbitrumToken,
  l1ProxyAdmin: ProxyAdmin,
  l1ReverseCustomGateway: L1ForceOnlyReverseCustomGateway,
  l2Token: L2ArbitrumToken,
  novaToken: L2CustomGatewayToken,
  ethProvider: Provider
) {
  //// check proxy admin
  assertEquals(
    await getProxyOwner(l1Token.address, ethProvider),
    l1ProxyAdmin.address,
    "L1ProxyAdmin should be L1ArbitrumToken's proxy admin"
  );

  //// check initialization params are correctly set
  assertEquals(await l1Token.name(), "Arbitrum", "Incorrect token name set for L1Token");
  assertEquals(await l1Token.symbol(), "ARB", "Incorrect token symbol set on L1Token");
  assertEquals(
    await l1Token.arbOneGateway(),
    l1ReverseCustomGateway.address,
    "Incorrect arb gateway set on L1Token"
  );
  assertEquals(
    await l1Token.novaGateway(),
    GovernanceConstants.L1_NOVA_GATEWAY,
    "Incorrect Nova gateway set on L1Token"
  );
  assertEquals(
    await l1Token.novaRouter(),
    GovernanceConstants.L1_NOVA_ROUTER,
    "Incorrect Nova router set on L1Token"
  );

  //// check token registration was successful for ArbOne
  const arbGateway = L1ForceOnlyReverseCustomGateway__factory.connect(
    await l1Token.arbOneGateway(),
    ethProvider
  );
  const arbRouter = L1GatewayRouter__factory.connect(await arbGateway.router(), ethProvider);
  assertEquals(
    await arbGateway.l1ToL2Token(l1Token.address),
    l2Token.address,
    "Incorrect L1Token to L2Token mapping on Arb (reverse) gateway"
  );
  assertEquals(
    await arbRouter.l1TokenToGateway(l1Token.address),
    arbGateway.address,
    "Incorrect L1Token to Arb gateway mapping on Arb router"
  );

  //// check token registration was successful for Nova
  const novaGateway = L1CustomGateway__factory.connect(await l1Token.novaGateway(), ethProvider);
  const novaRouter = L1GatewayRouter__factory.connect(await l1Token.novaRouter(), ethProvider);
  assertEquals(
    await novaGateway.l1ToL2Token(l1Token.address),
    novaToken.address,
    "Incorrect L1Token to NovaToken mapping on Nova gateway"
  );
  assertEquals(
    await novaRouter.l1TokenToGateway(l1Token.address),
    novaGateway.address,
    "Incorrect L1Token to Nova gateway mapping on Nova router"
  );
}

/**
 * Verify:
 * - roles are correctly assigned
 */
async function verifyL1UpgradeExecutor(
  l1Executor: UpgradeExecutor,
  l1Timelock: L1ArbitrumTimelock,
  l1ProxyAdmin: ProxyAdmin,
  ethProvider: Provider
) {
  //// check proxy admin
  assertEquals(
    await getProxyOwner(l1Executor.address, ethProvider),
    l1ProxyAdmin.address,
    "L1ProxyAdmin should be L1UpgradeExecutor's proxy admin"
  );

  //// check assigned/revoked roles are correctly set
  const adminRole = await l1Executor.ADMIN_ROLE();
  const executorRole = await l1Executor.EXECUTOR_ROLE();

  assert(
    await l1Executor.hasRole(adminRole, l1Executor.address),
    "L1UpgradeExecutor should have admin role on itself"
  );
  assert(
    await l1Executor.hasRole(executorRole, GovernanceConstants.L1_9_OF_12_SECURITY_COUNCIL),
    "L1 9/12 council should have executor role on L1 upgrade executor"
  );
  assert(
    await l1Executor.hasRole(executorRole, l1Timelock.address),
    "L1Timelock should have executor role on L1 upgrade executor"
  );
}

/**
 * Verify:
 * - initialization params are correctly set
 * - roles are correctly assigned
 */
async function verifyL1Timelock(
  l1Timelock: L1ArbitrumTimelock,
  l1Executor: UpgradeExecutor,
  l1GovernanceFactory: L1GovernanceFactory,
  l2Timelock: ArbitrumTimelock,
  l1ProxyAdmin: ProxyAdmin,
  ethProvider: Provider
) {
  //// check proxy admin
  assertEquals(
    await getProxyOwner(l1Timelock.address, ethProvider),
    l1ProxyAdmin.address,
    "L1ProxyAdmin should be L1ArbitrumTimelock's proxy admin"
  );

  //// check initialization params are correctly set
  assertEquals(
    (await l1Timelock.getMinDelay()).toString(),
    GovernanceConstants.L1_TIMELOCK_DELAY.toString(),
    "L1 timelock has incorrect min delay"
  );
  assertEquals(
    await l1Timelock.governanceChainInbox(),
    GovernanceConstants.L1_ARB_INBOX,
    "Incorrect governance chain inbox set on L1 timelock"
  );
  assertEquals(
    await l1Timelock.l2Timelock(),
    l2Timelock.address,
    "Incorrect L2 timelock reference set on L1 timelock"
  );

  //// check assigned/revoked roles are correctly set
  const proposerRole = await l1Timelock.PROPOSER_ROLE();
  const cancellerRole = await l1Timelock.CANCELLER_ROLE();
  const executorRole = await l1Timelock.EXECUTOR_ROLE();
  const timelockAdminRole = await l1Timelock.TIMELOCK_ADMIN_ROLE();

  assert(
    await l1Timelock.hasRole(
      proposerRole,
      await IInbox__factory.connect(GovernanceConstants.L1_ARB_INBOX, ethProvider).bridge()
    ),
    "Bridge should have proposer role on L1 timelock"
  );
  assert(
    await l1Timelock.hasRole(executorRole, ZERO_ADDRESS),
    "Executor role should be assigned to zero address on L1 timelock"
  );
  assert(
    await l1Timelock.hasRole(cancellerRole, GovernanceConstants.L1_9_OF_12_SECURITY_COUNCIL),
    "L1 9/12 council should have canceller role on L1 timelock"
  );
  assert(
    await l1Timelock.hasRole(timelockAdminRole, l1Executor.address),
    "L1UpgradeExecutor should have timelock admin role on L1 timelock"
  );
  assert(
    !(await l1Timelock.hasRole(timelockAdminRole, l1Timelock.address)),
    "L1Timelock should not have timelock admin role on itself"
  );
  assert(
    !(await l1Timelock.hasRole(timelockAdminRole, l1GovernanceFactory.address)),
    "L1GovernanceFactory should not have timelock admin role on L1 timelock"
  );
}

/**
 * Verify:
 * - proxy admin ownership
 */
async function verifyL1ProxyAdmin(l1ProxyAdmin: ProxyAdmin, l1Executor: UpgradeExecutor) {
  //// check ownership
  assertEquals(
    await l1ProxyAdmin.owner(),
    l1Executor.address,
    "L1UpgradeExecutor should be L1ProxyAdmin's owner"
  );
}

/**
 * Verify:
 * - proxy admin is correct
 * - initialization params are correctly set
 */
async function verifyL1ReverseGateway(
  l1ReverseGateway: L1ForceOnlyReverseCustomGateway,
  l2ReverseGateway: L2ReverseCustomGateway,
  l1ProxyAdmin: ProxyAdmin,
  ethProvider: Provider,
  ethDeployerAddress: string
) {
  //// check proxy admin
  assertEquals(
    await getProxyOwner(l1ReverseGateway.address, ethProvider),
    l1ProxyAdmin.address,
    "L1ProxyAdmin should be l1ReverseGateway's proxy admin"
  );

  // check owner
  assertEquals(
    await l1ReverseGateway.owner(),
    ethDeployerAddress,
    "EthDeployer should be l1ReverseGateway's owner"
  );

  /// check initialization params
  assertEquals(
    await l1ReverseGateway.counterpartGateway(),
    l2ReverseGateway.address,
    "Incorrect counterpart gateway set for l1ReverseGateway"
  );
  assertEquals(
    await l1ReverseGateway.inbox(),
    GovernanceConstants.L1_ARB_INBOX,
    "Incorrect inbox set for l1ReverseGateway"
  );
  assertEquals(
    await l1ReverseGateway.router(),
    GovernanceConstants.L1_ARB_ROUTER,
    "Incorrect router set for l1ReverseGateway"
  );
}

/**
 * Verify:
 * - ownership
 * - factory has completed job
 */
async function verifyL2GovernanceFactory(
  l2GovernanceFactory: L2GovernanceFactory,
  arbDeployerAddress: string
) {
  //// check ownership
  assertEquals(
    await l2GovernanceFactory.owner(),
    arbDeployerAddress,
    "ArbDeployer should be L2GovernanceFactory's owner"
  );

  // check factory has completed job
  // 2 == Step.Complete
  assertEquals(
    (await l2GovernanceFactory.step()).toString(),
    "2",
    "L2 governance factory should be in 'Complete'(2) step"
  );
}

/**
 * Verify:
 * - ownership
 * - initialization params are correctly set
 * - roles are correctly assigned
 */
async function verifyArbitrumTimelock(
  l2Timelock: ArbitrumTimelock,
  l2CoreGovernor: L2ArbitrumGovernor,
  l2Executor: UpgradeExecutor,
  l2GovernanceFactory: L2GovernanceFactory,
  l2ProxyAdmin: ProxyAdmin,
  arbProvider: Provider
) {
  //// check proxy admin
  assertEquals(
    await getProxyOwner(l2Timelock.address, arbProvider),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be L2 core ArbitrumTimelock's proxy admin"
  );

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
 * - ownership
 * - initialization params are correctly set
 */
async function verifyL2CoreGovernor(
  l2CoreGovernor: L2ArbitrumGovernor,
  l2Token: L2ArbitrumToken,
  l2Timelock: ArbitrumTimelock,
  l2Executor: UpgradeExecutor,
  l2ProxyAdmin: ProxyAdmin,
  arbProvider: Provider
) {
  //// check ownership
  assertEquals(
    await getProxyOwner(l2CoreGovernor.address, arbProvider),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be core L2ArbitrumGovernor's proxy admin"
  );
  assertEquals(
    await l2CoreGovernor.owner(),
    l2Executor.address,
    "L2UpgradeExecutor should be core L2ArbitrumGovernor's owner"
  );

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
 * - ownership
 * - roles are correctly assigned
 */
async function verifyL2UpgradeExecutor(
  l2Executor: UpgradeExecutor,
  l1Timelock: L1ArbitrumTimelock,
  l2ProxyAdmin: ProxyAdmin,
  arbProvider: Provider
) {
  //// check proxy admin
  assertEquals(
    await getProxyOwner(l2Executor.address, arbProvider),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be L2UpgradeExecutor's proxy admin"
  );

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
  l1Token: L1ArbitrumToken,
  l2Executor: UpgradeExecutor,
  l2ProxyAdmin: ProxyAdmin,
  l2TokenDistributor: TokenDistributor,
  arbProvider: Provider
) {
  //// check ownership
  assertEquals(
    await getProxyOwner(l2Token.address, arbProvider),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be L2ArbitrumToken's proxy admin"
  );
  assertEquals(
    await l2Token.owner(),
    l2Executor.address,
    "L2UpgradeExecutor should be L2ArbitrumToken's owner"
  );

  //// check initialization params
  assertEquals(await l2Token.name(), "Arbitrum", "L2Token name should be Arbitrum");
  assertEquals(await l2Token.symbol(), "ARB", "L2Token symbol should be ARB");
  assertNumbersEquals(
    await l2Token.totalSupply(),
    ethers.utils.parseEther(GovernanceConstants.L2_TOKEN_INITIAL_SUPPLY.toString()),
    "L2Token has incorrect total supply"
  );
  assertEquals(
    await l2Token.l1Address(),
    l1Token.address,
    "Incorrect L1Token reference for L2Token"
  );

  // check balances
  const arbTreasuryBalance = await l2Token.balanceOf(arbTreasury.address);
  const tokenDistributorBalance = await l2Token.balanceOf(l2TokenDistributor.address);
  assertNumbersEquals(
    arbTreasuryBalance,
    parseEther(GovernanceConstants.L2_NUM_OF_TOKENS_FOR_TREASURY),
    "Incorrect initial L2Token balance for ArbTreasury"
  );
  assertNumbersEquals(
    tokenDistributorBalance,
    parseEther(GovernanceConstants.L2_NUM_OF_TOKENS_FOR_CLAIMING),
    "Incorrect initial L2Token balance for TokenDistributor"
  );
  assertNumbersEquals(
    arbTreasuryBalance.add(tokenDistributorBalance),
    await l2Token.totalSupply(),
    "ArbTreasury and TokenDistributor should own all the tokens "
  );
}

/**
 * Verify:
 * - ownership
 * - initialization params are correctly set
 */
async function verifyL2TreasuryGovernor(
  l2TreasuryGoverner: L2ArbitrumGovernor,
  l2Token: L2ArbitrumToken,
  l2Executor: UpgradeExecutor,
  l2ProxyAdmin: ProxyAdmin,
  arbProvider: Provider
) {
  //// check ownership
  assertEquals(
    await getProxyOwner(l2TreasuryGoverner.address, arbProvider),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be treasury L2ArbitrumGovernor's proxy admin"
  );
  assertEquals(
    await l2TreasuryGoverner.owner(),
    l2Executor.address,
    "L2UpgradeExecutor should be treasury L2ArbitrumGovernor's owner"
  );

  //// check initialization params are correctly set
  assertEquals(
    await l2TreasuryGoverner.name(),
    "L2ArbitrumGovernor",
    "Incorrect L2 core governor's name"
  );
  assertNumbersEquals(
    await l2TreasuryGoverner.votingDelay(),
    BigNumber.from(GovernanceConstants.L2_VOTING_DELAY),
    "Incorrect voting delay set for L2 treasury governor"
  );
  assertNumbersEquals(
    await l2TreasuryGoverner.votingPeriod(),
    BigNumber.from(GovernanceConstants.L2_VOTING_PERIOD),
    "Incorrect voting period set for L2 treasury governor"
  );
  assertNumbersEquals(
    await l2TreasuryGoverner.proposalThreshold(),
    BigNumber.from(GovernanceConstants.L2_PROPOSAL_TRESHOLD),
    "Incorrect proposal threshold set for L2 treasury governor"
  );
  assertEquals(
    await l2TreasuryGoverner.token(),
    l2Token.address,
    "Incorrect token set for L2 treasury governor"
  );
  assertNumbersEquals(
    await l2TreasuryGoverner["quorumNumerator()"](),
    BigNumber.from(GovernanceConstants.L2_TREASURY_QUORUM_TRESHOLD),
    "Incorrect quorum treshold set for L2 treasury governor"
  );
  assertNumbersEquals(
    await l2TreasuryGoverner.lateQuorumVoteExtension(),
    BigNumber.from(GovernanceConstants.L2_MIN_PERIOD_AFTER_QUORUM),
    "Incorrect min period after quorum set for L2 treasury governor"
  );
}

/**
 * Verify:
 * - ownership
 * - initialization params are correctly set
 */
async function verifyL2TreasuryTimelock(
  l2TreasuryTimelock: ArbitrumTimelock,
  l2TreasuryGoverner: L2ArbitrumGovernor,
  l2UpgradeExecutor: UpgradeExecutor,
  l2GovernanceFactory: L2GovernanceFactory,
  l2ProxyAdmin: ProxyAdmin,
  arbProvider: Provider
) {
  //// check proxy admin
  assertEquals(
    await getProxyOwner(l2TreasuryTimelock.address, arbProvider),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be L2 treasury timelock's proxy admin"
  );

  //// check initialization params are correctly set
  assertNumbersEquals(
    await l2TreasuryTimelock.getMinDelay(),
    BigNumber.from(0),
    "Incorrect min delay set for L2 treasury governor"
  );

  //// check assigned/revoked roles are correctly set
  const proposerRole = await l2TreasuryTimelock.PROPOSER_ROLE();
  const cancellerRole = await l2TreasuryTimelock.CANCELLER_ROLE();
  const executorRole = await l2TreasuryTimelock.EXECUTOR_ROLE();
  const timelockAdminRole = await l2TreasuryTimelock.TIMELOCK_ADMIN_ROLE();

  assert(
    await l2TreasuryTimelock.hasRole(proposerRole, l2TreasuryGoverner.address),
    "L2 treasury governor should have proposer role on L2 treasury timelock"
  );
  assert(
    await l2TreasuryTimelock.hasRole(cancellerRole, l2TreasuryGoverner.address),
    "L2 treasury governor should have canceller role on L2 treasury timelock"
  );
  assert(
    await l2TreasuryTimelock.hasRole(executorRole, ZERO_ADDRESS),
    "Executor role should be assigned to zero address on L2 treasury timelock"
  );
  assert(
    await l2TreasuryTimelock.hasRole(timelockAdminRole, l2UpgradeExecutor.address),
    "L2 upgrade executor should have timelock admin role on L2 treasury timelock"
  );
  assert(
    !(await l2TreasuryTimelock.hasRole(timelockAdminRole, l2TreasuryTimelock.address)),
    "L2 treasury timelock should not have timelock admin role on itself"
  );
  assert(
    !(await l2TreasuryTimelock.hasRole(timelockAdminRole, l2GovernanceFactory.address)),
    "L2 governance factory should not have timelock admin role on L2 treasury timelock"
  );
}

/**
 * Verify:
 * - ownership
 * - delegate is properly set
 */
async function verifyL2ArbTreasury(
  l2ArbTreasury: FixedDelegateErc20Wallet,
  l2Token: L2ArbitrumToken,
  l2TreasuryGoverner: L2ArbitrumGovernor,
  l2ProxyAdmin: ProxyAdmin,
  arbProvider: Provider
) {
  //// check ownership
  assertEquals(
    await getProxyOwner(l2ArbTreasury.address, arbProvider),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be arbTreasury's proxy admin"
  );
  assertEquals(
    await l2ArbTreasury.owner(),
    await l2TreasuryGoverner.timelock(),
    "L2TreasuryGoverner's timelock should be arbTreasury's owner"
  );

  //// check delegation
  const voteToken = IVotesUpgradeable__factory.connect(l2Token.address, arbProvider);

  assertEquals(
    await voteToken.delegates(l2ArbTreasury.address),
    await l2TreasuryGoverner.EXCLUDE_ADDRESS(),
    "L2ArbTreasury should delegate to EXCLUDE_ADDRESS"
  );
}

/**
 * Verify:
 * - initialization params are correctly set
 */
async function verifyL2TokenDistributor(
  l2TokenDistributor: TokenDistributor,
  l2Token: L2ArbitrumToken,
  l2Executor: UpgradeExecutor,
  l2CoreGovernor: L2ArbitrumGovernor,
  arbProvider: Provider
) {
  //// check ownership
  assertEquals(
    await l2TokenDistributor.owner(),
    l2Executor.address,
    "L2UpgradeExecutor should be L2 TokenDistributor's owner"
  );

  //// check token balances
  assertNumbersEquals(
    await l2Token.balanceOf(l2TokenDistributor.address),
    parseEther(GovernanceConstants.L2_NUM_OF_TOKENS_FOR_CLAIMING),
    "Incorrect initial L2Token balance for TokenDistributor"
  );
  assertNumbersEquals(
    await l2TokenDistributor.totalClaimable(),
    parseEther(GovernanceConstants.L2_NUM_OF_TOKENS_FOR_CLAIMING),
    "Incorrect totalClaimable amount for TokenDistributor"
  );

  //// check initialization params
  assertEquals(
    await l2TokenDistributor.token(),
    l2Token.address,
    "Incorrect token reference set for TokenDistributor"
  );
  assertEquals(
    await l2TokenDistributor.sweepReceiver(),
    GovernanceConstants.L2_SWEEP_RECECIVER,
    "Incorrect sweep receiver set for TokenDistributor"
  );
  assertNumbersEquals(
    await l2TokenDistributor.claimPeriodStart(),
    BigNumber.from(GovernanceConstants.L2_CLAIM_PERIOD_START),
    "Incorrect claim period start set for TokenDistributor"
  );
  assertNumbersEquals(
    await l2TokenDistributor.claimPeriodEnd(),
    BigNumber.from(GovernanceConstants.L2_CLAIM_PERIOD_END),
    "Incorrect claim period end set for TokenDistributor"
  );

  //// check delegation
  const voteToken = IVotesUpgradeable__factory.connect(l2Token.address, arbProvider);
  assertEquals(
    await voteToken.delegates(l2TokenDistributor.address),
    await l2CoreGovernor.EXCLUDE_ADDRESS(),
    "L2TokenDistributor should delegate to EXCLUDE_ADDRESS"
  );
}

/**
 * Verify:
 * - ownership
 */
async function verifyL2ProxyAdmin(l2ProxyAdmin: ProxyAdmin, l2Executor: UpgradeExecutor) {
  //// check ownership
  assertEquals(
    await l2ProxyAdmin.owner(),
    l2Executor.address,
    "L2UpgradeExecutor should be L2ProxyAdmin's owner"
  );
}

/**
 * Verify:
 * - proxy admin is correct
 * - initialization params are correctly set
 */
async function verifyL2ReverseGateway(
  l2ReverseGateway: L2ReverseCustomGateway,
  l1ReverseGateway: L1ForceOnlyReverseCustomGateway,
  l2ProxyAdmin: ProxyAdmin,
  arbProvider: Provider
) {
  //// check proxy admin
  assertEquals(
    await getProxyOwner(l2ReverseGateway.address, arbProvider),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be l2ReverseGateway's proxy admin"
  );

  /// check initialization params
  assertEquals(
    await l2ReverseGateway.counterpartGateway(),
    l1ReverseGateway.address,
    "Incorrect counterpart gateway set for l2ReverseGateway"
  );
  assertEquals(
    await l2ReverseGateway.router(),
    GovernanceConstants.L2_GATEWAY_ROUTER,
    "Incorrect router set for 21ReverseGateway"
  );
}

/**
 * Verify:
 * - roles are correctly assigned
 */
async function verifyNovaUpgradeExecutor(
  novaUpgradeExecutor: UpgradeExecutor,
  l1Timelock: L1ArbitrumTimelock,
  novaProxyAdmin: ProxyAdmin,
  novaProvider: Provider
) {
  //// check proxy admin
  assertEquals(
    await getProxyOwner(novaUpgradeExecutor.address, novaProvider),
    novaProxyAdmin.address,
    "NovaProxyAdmin should be NovaUpgradeExecutor's proxy admin"
  );

  //// check assigned/revoked roles are correctly set
  const adminRole = await novaUpgradeExecutor.ADMIN_ROLE();
  const executorRole = await novaUpgradeExecutor.EXECUTOR_ROLE();

  assert(
    await novaUpgradeExecutor.hasRole(adminRole, novaUpgradeExecutor.address),
    "NovaUpgradeExecutor should have admin role on itself"
  );
  assert(
    await novaUpgradeExecutor.hasRole(
      executorRole,
      GovernanceConstants.NOVA_9_OF_12_SECURITY_COUNCIL
    ),
    "Nova 9/12 council should have executor role on Nova upgrade executor"
  );
  const l1TimelockAddressAliased = new Address(l1Timelock.address).applyAlias().value;
  assert(
    await novaUpgradeExecutor.hasRole(executorRole, l1TimelockAddressAliased),
    "L1Timelock should have executor role on Nova upgrade executor"
  );
}

/**
 * Verify:
 * - initialization params are correctly set
 */
async function verifyNovaToken(
  novaToken: L2CustomGatewayToken,
  l1Token: L1ArbitrumToken,
  novaProxyAdmin: ProxyAdmin,
  novaProvider: Provider
) {
  //// check proxy admin
  assertEquals(
    await getProxyOwner(novaToken.address, novaProvider),
    novaProxyAdmin.address,
    "NovaProxyAdmin should be NovaToken's owner"
  );

  //// check initialization params
  assertEquals(
    await novaToken.name(),
    GovernanceConstants.NOVA_TOKEN_NAME,
    "Incorrect token name set for Nova token"
  );
  assertEquals(
    await novaToken.symbol(),
    GovernanceConstants.NOVA_TOKEN_SYMBOL,
    "Incorrect token symbol set on Nova token"
  );
  assertEquals(
    (await novaToken.decimals()).toString(),
    GovernanceConstants.NOVA_TOKEN_DECIMALS.toString(),
    "Incorrect token decimals set on Nova token"
  );
  assertEquals(
    await novaToken.l2Gateway(),
    GovernanceConstants.NOVA_TOKEN_GATEWAY,
    "Incorrect L2 gateway set on Nova token"
  );
  assertEquals(
    await novaToken.l1Address(),
    l1Token.address,
    "Incorrect L1 token address set on Nova token"
  );
}

/**
 * Verify:
 * - proxy admin ownership
 */
async function verifyNovaProxyAdmin(
  novaProxyAdmin: ProxyAdmin,
  novaUpgradeExecutor: UpgradeExecutor
) {
  assertEquals(
    await novaProxyAdmin.owner(),
    novaUpgradeExecutor.address,
    "NovaUpgradeExecutor should be NovaProxyAdmin's owner"
  );
}

/**
 * Load contracts by reading addresses from file `DEPLOYED_CONTRACTS_FILE_NAME` and return loaded contracts in key-value format.
 *
 * @param ethProvider
 * @param arbProvider
 * @param novaProvider
 * @returns
 */
async function loadContracts(
  ethProvider: Provider,
  arbProvider: Provider,
  novaProvider: Provider
): Promise<{ [key: string]: any }> {
  const contractAddresses = require("../" + DEPLOYED_CONTRACTS_FILE_NAME);
  let contracts: { [key: string]: any } = {};

  // load L1 contracts
  contracts["l1GovernanceFactory"] = L1GovernanceFactory__factory.connect(
    contractAddresses["l1GovernanceFactory"],
    ethProvider
  );
  contracts["l1TokenProxy"] = L1ArbitrumToken__factory.connect(
    contractAddresses["l1TokenProxy"],
    ethProvider
  );
  contracts["l1Executor"] = UpgradeExecutor__factory.connect(
    contractAddresses["l1Executor"],
    ethProvider
  );
  contracts["l1Timelock"] = L1ArbitrumTimelock__factory.connect(
    contractAddresses["l1Timelock"],
    ethProvider
  );
  contracts["l1ProxyAdmin"] = ProxyAdmin__factory.connect(
    contractAddresses["l1ProxyAdmin"],
    ethProvider
  );
  contracts["l1ProxyAdmin"] = ProxyAdmin__factory.connect(
    contractAddresses["l1ProxyAdmin"],
    ethProvider
  );
  contracts["l1ReverseCustomGatewayProxy"] = L1ForceOnlyReverseCustomGateway__factory.connect(
    contractAddresses["l1ReverseCustomGatewayProxy"],
    ethProvider
  );

  // load L2 contracts
  contracts["l2Token"] = L2ArbitrumToken__factory.connect(
    contractAddresses["l2Token"],
    arbProvider
  );
  contracts["l2Executor"] = UpgradeExecutor__factory.connect(
    contractAddresses["l2Executor"],
    arbProvider
  );
  contracts["l2GovernanceFactory"] = L2GovernanceFactory__factory.connect(
    contractAddresses["l2GovernanceFactory"],
    arbProvider
  );
  contracts["l2CoreGoverner"] = L2ArbitrumGovernor__factory.connect(
    contractAddresses["l2CoreGoverner"],
    arbProvider
  );
  contracts["l2CoreTimelock"] = ArbitrumTimelock__factory.connect(
    contractAddresses["l2CoreTimelock"],
    arbProvider
  );
  contracts["l2ProxyAdmin"] = ProxyAdmin__factory.connect(
    contractAddresses["l2ProxyAdmin"],
    arbProvider
  );
  contracts["l2TreasuryGoverner"] = L2ArbitrumGovernor__factory.connect(
    contractAddresses["l2TreasuryGoverner"],
    arbProvider
  );
  contracts["l2ArbTreasury"] = FixedDelegateErc20Wallet__factory.connect(
    contractAddresses["l2ArbTreasury"],
    arbProvider
  );
  contracts["l2TokenDistributor"] = TokenDistributor__factory.connect(
    contractAddresses["l2TokenDistributor"],
    arbProvider
  );
  contracts["l2ReverseCustomGatewayProxy"] = L2ReverseCustomGateway__factory.connect(
    contractAddresses["l2ReverseCustomGatewayProxy"],
    arbProvider
  );

  // load Nova contracts
  contracts["novaProxyAdmin"] = ProxyAdmin__factory.connect(
    contractAddresses["novaProxyAdmin"],
    novaProvider
  );
  contracts["novaUpgradeExecutorProxy"] = UpgradeExecutor__factory.connect(
    contractAddresses["novaUpgradeExecutorProxy"],
    novaProvider
  );
  contracts["novaTokenProxy"] = L2CustomGatewayToken__factory.connect(
    contractAddresses["novaTokenProxy"],
    novaProvider
  );

  return contracts;
}

/**
 * Gets the proxy owner by reading storage
 *
 * @param contractAddress
 * @param provider
 * @returns
 */
async function getProxyOwner(contractAddress: string, provider: Provider) {
  // gets address in format like 0x000000000000000000000000a898b332e65d0cc9cb538495ff145983806d8453
  const ownerStorageValue = await provider.getStorageAt(
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

/**
 * Simple assertion function for strings
 *
 * @param actual
 * @param expected
 * @param message
 */
async function assertEquals(actual: string, expected: string, message: string) {
  if (actual != expected) {
    console.error("Actual: ", actual);
    console.error("Expected: ", expected);
    throw new Error(message);
  }
}

/**
 * Simple assertion function for BigNumbers
 *
 * @param actual
 * @param expected
 * @param message
 */
async function assertNumbersEquals(actual: BigNumber, expected: BigNumber, message: string) {
  if (!actual.eq(expected)) {
    console.error("Actual: ", actual.toString());
    console.error("Expected: ", expected.toString());
    throw new Error(message);
  }
}

/**
 * Simple assertion function
 * @param condition
 * @param message
 */
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
