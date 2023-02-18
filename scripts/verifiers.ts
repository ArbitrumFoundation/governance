import { BigNumber, constants, ethers } from "ethers";
import {
  ArbitrumDAOConstitution,
  ArbitrumDAOConstitution__factory,
  ArbitrumTimelock,
  ArbitrumTimelock__factory,
  ArbitrumVestingWallet__factory,
  ArbitrumVestingWalletsFactory,
  ArbitrumVestingWalletsFactory__factory,
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
} from "../token-bridge-contracts/build/types";
import {
  DeployProgressCache,
  getProviders,
  isDeployingToNova,
  loadDeployedContracts,
} from "./providerSetup";
import { Address, L2Network } from "@arbitrum/sdk";
import { parseEther } from "ethers/lib/utils";
import { L1CustomGateway__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L1CustomGateway__factory";
import { L1GatewayRouter__factory } from "@arbitrum/sdk/dist/lib/abi/factories/L1GatewayRouter__factory";
import { Provider } from "@ethersproject/providers";
import { getRecipientsDataFromContractEvents } from "./tokenDistributorHelper";
import dotenv from "dotenv";
import { Recipients, assert, assertEquals, assertNumbersEquals, getProxyOwner } from "./testUtils";
import { WalletCreatedEvent } from "../typechain-types/src/ArbitrumVestingWalletFactory.sol/ArbitrumVestingWalletsFactory";
import { TransferEvent } from "../typechain-types/src/Util.sol/IERC20VotesUpgradeable";
import { OwnershipTransferredEvent } from "../typechain-types/src/L2ArbitrumToken";
const deadAddress = "0x000000000000000000000000000000000000dEaD";

dotenv.config();

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

/**
 * Main function that verifies governance deployment was successful.
 */
export const verifyDeployment = async () => {
  const {
    ethProvider,
    arbProvider,
    novaProvider,
    deployerConfig,
    arbNetwork: arbOneNetwork,
    novaNetwork,
  } = await getProviders();

  const deployedContracts = loadDeployedContracts();
  const l1Contracts = loadL1Contracts(ethProvider, deployedContracts);
  const arbContracts = loadArbContracts(arbProvider, deployedContracts);
  const novaContracts = isDeployingToNova()
    ? loadNovaContracts(novaProvider, deployedContracts)
    : undefined;

  console.log("Verify L1 contracts are properly deployed");
  await verifyL1GovernanceFactory(l1Contracts["l1GovernanceFactory"]);
  await verifyL1Token(
    l1Contracts.l1TokenProxy,
    l1Contracts.l1ProxyAdmin,
    l1Contracts.l1ReverseCustomGatewayProxy,
    ethProvider,
    novaNetwork
  );
  await verifyL1UpgradeExecutor(
    l1Contracts.l1Executor,
    l1Contracts.l1Timelock,
    l1Contracts.l1ProxyAdmin,
    ethProvider,
    deployerConfig
  );
  await verifyL1Timelock(
    l1Contracts.l1Timelock,
    l1Contracts.l1Executor,
    l1Contracts.l1GovernanceFactory,
    arbContracts.l2CoreTimelock,
    l1Contracts.l1ProxyAdmin,
    ethProvider,
    arbOneNetwork,
    deployerConfig
  );
  await verifyL1ProxyAdmin(l1Contracts.l1ProxyAdmin, l1Contracts.l1Executor);
  await verifyL1ReverseGateway(
    l1Contracts.l1ReverseCustomGatewayProxy,
    arbContracts.l2ReverseCustomGatewayProxy,
    l1Contracts.l1ProxyAdmin,
    l1Contracts.l1Executor,
    ethProvider,
    arbOneNetwork
  );

  //// L2 contracts
  console.log("Verify L2 contracts are properly deployed");
  await verifyArbitrumTimelock(
    arbContracts.l2CoreTimelock,
    arbContracts.l2CoreGoverner,
    arbContracts.l2Executor,
    arbContracts.l2GovernanceFactory,
    arbContracts.l2ProxyAdmin,
    arbProvider,
    deployerConfig
  );
  await verifyL2GovernanceFactory(arbContracts.l2GovernanceFactory);
  await verifyL2CoreGovernor(
    arbContracts.l2CoreGoverner,
    arbContracts.l2Token,
    arbContracts.l2CoreTimelock,
    arbContracts.l2Executor,
    arbContracts.l2ProxyAdmin,
    arbProvider,
    deployerConfig
  );
  await verifyL2UpgradeExecutor(
    arbContracts.l2Executor,
    l1Contracts.l1Timelock,
    arbContracts.l2ProxyAdmin,
    arbProvider,
    deployerConfig
  );
  await verifyL2Token(
    arbContracts.l2Token,
    l1Contracts.l1TokenProxy,
    arbContracts.l2Executor,
    arbContracts.l2ProxyAdmin,
    arbProvider,
    ethProvider,
    deployerConfig
  );

  await verifyL2TreasuryGovernor(
    arbContracts.l2TreasuryGoverner,
    arbContracts.l2Token,
    arbContracts.l2Executor,
    arbContracts.l2ProxyAdmin,
    arbProvider,
    deployerConfig
  );

  const l2TreasuryTimelock = ArbitrumTimelock__factory.connect(
    await arbContracts.l2TreasuryGoverner.timelock(),
    arbProvider
  );
  await verifyL2TreasuryTimelock(
    l2TreasuryTimelock,
    arbContracts.l2TreasuryGoverner,
    arbContracts.l2Executor,
    arbContracts.l2GovernanceFactory,
    arbContracts.l2ProxyAdmin,
    arbProvider,
    deployerConfig
  );
  await verifyL2ArbTreasury(
    arbContracts.l2ArbTreasury,
    arbContracts.l2Token,
    arbContracts.l2TreasuryGoverner,
    arbContracts.l2ProxyAdmin,
    arbProvider
  );

  await verifyArbitrumDAOConstitution(
    arbContracts.arbitrumDAOConstitution,
    arbContracts.l2Executor,
    deployerConfig
  );
  await verifyL2ProxyAdmin(arbContracts.l2ProxyAdmin, arbContracts.l2Executor);
  await verifyL2ReverseGateway(
    arbContracts.l2ReverseCustomGatewayProxy,
    l1Contracts.l1ReverseCustomGatewayProxy,
    arbContracts.l2ProxyAdmin,
    arbProvider,
    arbOneNetwork
  );

  //// Nova contracts
  if (isDeployingToNova()) {
    console.log("Verify Nova contracts are properly deployed");
    await verifyNovaUpgradeExecutor(
      novaContracts!.novaUpgradeExecutorProxy,
      l1Contracts.l1Timelock,
      novaContracts!.novaProxyAdmin,
      novaProvider,
      deployerConfig
    );
    await verifyNovaToken(
      novaContracts!.novaTokenProxy,
      l1Contracts.l1TokenProxy,
      novaContracts!.novaProxyAdmin,
      novaProvider,
      ethProvider,
      novaNetwork,
      deployerConfig
    );
    await verifyNovaProxyAdmin(
      novaContracts!.novaProxyAdmin,
      novaContracts!.novaUpgradeExecutorProxy
    );
  }
};

/**
 * Verify:
 * - factory ownership
 */
async function verifyL1GovernanceFactory(l1GovernanceFactory: L1GovernanceFactory) {
  assertEquals(
    await l1GovernanceFactory.owner(),
    deadAddress,
    "EthDeployer should be the dead address"
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
  ethProvider: Provider,
  novaNetwork: L2Network
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
    novaNetwork.tokenBridge.l1CustomGateway,
    "Incorrect Nova gateway set on L1Token"
  );
  assertEquals(
    await l1Token.novaRouter(),
    novaNetwork.tokenBridge.l1GatewayRouter,
    "Incorrect Nova router set on L1Token"
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
  ethProvider: Provider,
  config: {
    L1_9_OF_12_SECURITY_COUNCIL: string;
  }
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
    await l1Executor.hasRole(executorRole, config.L1_9_OF_12_SECURITY_COUNCIL),
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
  ethProvider: Provider,
  arbOneNetwork: L2Network,
  config: {
    L1_TIMELOCK_DELAY: number;
    L1_9_OF_12_SECURITY_COUNCIL: string;
  }
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
    config.L1_TIMELOCK_DELAY.toString(),
    "L1 timelock has incorrect min delay"
  );
  assertEquals(
    await l1Timelock.governanceChainInbox(),
    arbOneNetwork.ethBridge.inbox,
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
      await IInbox__factory.connect(arbOneNetwork.ethBridge.inbox, ethProvider).bridge()
    ),
    "Bridge should have proposer role on L1 timelock"
  );
  assert(
    await l1Timelock.hasRole(executorRole, ZERO_ADDRESS),
    "Executor role should be assigned to zero address on L1 timelock"
  );
  assert(
    await l1Timelock.hasRole(cancellerRole, config.L1_9_OF_12_SECURITY_COUNCIL),
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
  l1Executor: UpgradeExecutor,
  ethProvider: Provider,
  arbOneNetwork: L2Network
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
    l1Executor.address,
    "L1Executor should be l1ReverseGateway's owner"
  );

  /// check initialization params
  assertEquals(
    await l1ReverseGateway.counterpartGateway(),
    l2ReverseGateway.address,
    "Incorrect counterpart gateway set for l1ReverseGateway"
  );
  assertEquals(
    await l1ReverseGateway.inbox(),
    arbOneNetwork.ethBridge.inbox,
    "Incorrect inbox set for l1ReverseGateway"
  );
  assertEquals(
    await l1ReverseGateway.router(),
    arbOneNetwork.tokenBridge.l1GatewayRouter,
    "Incorrect router set for l1ReverseGateway"
  );
}

/**
 * Verify:
 * - ownership
 * - factory has completed job
 */
async function verifyL2GovernanceFactory(l2GovernanceFactory: L2GovernanceFactory) {
  //// check ownership
  assertEquals(
    await l2GovernanceFactory.owner(),
    deadAddress,
    "ArbDeployer should be the dead address"
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
  arbProvider: Provider,
  config: {
    L2_TIMELOCK_DELAY: number;
    L2_7_OF_12_SECURITY_COUNCIL: string;
    L2_9_OF_12_SECURITY_COUNCIL: string;
  }
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
    config.L2_TIMELOCK_DELAY.toString(),
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
    await l2Timelock.hasRole(proposerRole, config.L2_7_OF_12_SECURITY_COUNCIL.toString()),
    "L2 7/12 council should have proposer role on L2 timelock"
  );
  assert(
    !(await l2Timelock.hasRole(cancellerRole, config.L2_7_OF_12_SECURITY_COUNCIL.toString())),
    "L2 7/12 council should not have canceller role on L2 timelock"
  );
  assert(
    await l2Timelock.hasRole(cancellerRole, config.L2_9_OF_12_SECURITY_COUNCIL.toString()),
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
  arbProvider: Provider,
  config: {
    L2_VOTING_DELAY: number;
    L2_VOTING_PERIOD: number;
    L2_PROPOSAL_TRESHOLD: number;
    L2_CORE_QUORUM_TRESHOLD: number;
    L2_MIN_PERIOD_AFTER_QUORUM: number;
  }
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
    BigNumber.from(config.L2_VOTING_DELAY),
    "Incorrect voting delay set for L2 core governor"
  );
  assertNumbersEquals(
    await l2CoreGovernor.votingPeriod(),
    BigNumber.from(config.L2_VOTING_PERIOD),
    "Incorrect voting period set for L2 core governor"
  );
  assertNumbersEquals(
    await l2CoreGovernor.proposalThreshold(),
    BigNumber.from(config.L2_PROPOSAL_TRESHOLD),
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
    BigNumber.from(config.L2_CORE_QUORUM_TRESHOLD),
    "Incorrect quorum treshold set for L2 core governor"
  );
  assertNumbersEquals(
    await l2CoreGovernor.lateQuorumVoteExtension(),
    BigNumber.from(config.L2_MIN_PERIOD_AFTER_QUORUM),
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
  arbProvider: Provider,
  config: {
    L2_9_OF_12_SECURITY_COUNCIL: string;
  }
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
    await l2Executor.hasRole(executorRole, config.L2_9_OF_12_SECURITY_COUNCIL),
    "L2 9/12 council should have executor role on L2 upgrade executor"
  );
}

/**
 * Verify
 * - Token total supply is the same as config
 * - Treasury has correct amount
 * - Vested wallets deployed and received correct amounts
 * - Airdrop recipients received correct claim amounts
 * - Token distributor received correct amount
 * - Foundation received correct amount
 * - Team received correct amount
 * - Total transferred is same as total supply
 * - Initial recipient has no remaining tokens
 */
export async function verifyTokenDistribution(
  l2Token: L2ArbitrumToken,
  arbTreasury: FixedDelegateErc20Wallet,
  l2TokenDistributor: TokenDistributor,
  arbProvider: Provider,
  claimRecipients: Recipients,
  deploymentInfo: {
    distributorSetRecipientsStartBlock: number;
    distributorSetRecipientsEndBlock: number;
  },
  config: {
    L2_TOKEN_INITIAL_SUPPLY: string;
    L2_NUM_OF_TOKENS_FOR_TREASURY: string;
    L2_ADDRESS_FOR_FOUNDATION: string;
    L2_NUM_OF_TOKENS_FOR_FOUNDATION: string;
    L2_ADDRESS_FOR_TEAM: string;
    L2_NUM_OF_TOKENS_FOR_TEAM: string;
    L2_ADDRESS_FOR_DAO_RECIPIENTS: string;
    L2_NUM_OF_TOKENS_FOR_DAO_RECIPIENTS: string;
    L2_ADDRESS_FOR_INVESTORS: string;
    L2_NUM_OF_TOKENS_FOR_INVESTORS: string;
    L2_CLAIM_PERIOD_START: number;
    GET_LOGS_BLOCK_RANGE: number;
  }
) {
  assertNumbersEquals(
    await l2Token.totalSupply(),
    ethers.utils.parseEther(config.L2_TOKEN_INITIAL_SUPPLY),
    "L2Token has incorrect total supply"
  );

  const arbTreasuryBalance = await l2Token.balanceOf(arbTreasury.address);
  assertNumbersEquals(
    arbTreasuryBalance,
    parseEther(config.L2_NUM_OF_TOKENS_FOR_TREASURY),
    "Incorrect initial L2Token balance for ArbTreasury"
  );

  const initialSupplyRecipient = await getInitialSupplyRecipientAddr(arbProvider, l2Token);

  const initSupplyRecipientBalance = await l2Token.balanceOf(initialSupplyRecipient);
  assertNumbersEquals(
    initSupplyRecipientBalance,
    BigNumber.from(0),
    "Initial supply recipient still has tokens"
  );

  const recipientTotals = Object.values(claimRecipients).reduce((a, b) => a.add(b));
  const tokenDistributorBalance = await l2Token.balanceOf(l2TokenDistributor.address);
  await verifyClaimsSetCorrectly(l2TokenDistributor, claimRecipients, deploymentInfo, config);
  assertNumbersEquals(
    tokenDistributorBalance,
    recipientTotals,
    "Incorrect initial L2Token balance for TokenDistributor"
  );

  const foundationBalance = await l2Token.balanceOf(config.L2_ADDRESS_FOR_FOUNDATION);
  assertNumbersEquals(
    foundationBalance,
    parseEther(config.L2_NUM_OF_TOKENS_FOR_FOUNDATION),
    "Incorrect initial L2Token balance for foundation"
  );

  const teamBalance = await l2Token.balanceOf(config.L2_ADDRESS_FOR_TEAM);
  assertNumbersEquals(
    teamBalance,
    parseEther(config.L2_NUM_OF_TOKENS_FOR_TEAM),
    "Incorrect initial L2Token balance for team"
  );

  const daoBalance = await l2Token.balanceOf(config.L2_ADDRESS_FOR_DAO_RECIPIENTS);
  assertNumbersEquals(
    daoBalance,
    parseEther(config.L2_NUM_OF_TOKENS_FOR_DAO_RECIPIENTS),
    "Incorrect initial L2Token balance for dao recipients"
  );

  const vestingBalance = await l2Token.balanceOf(config.L2_ADDRESS_FOR_INVESTORS);
  assertNumbersEquals(
    vestingBalance,
    parseEther(config.L2_NUM_OF_TOKENS_FOR_INVESTORS),
    "Incorrect initial L2Token balance for investors"
  );

  assertNumbersEquals(
    arbTreasuryBalance
      .add(tokenDistributorBalance)
      .add(vestingBalance)
      .add(foundationBalance)
      .add(teamBalance)
      .add(daoBalance),
    await l2Token.totalSupply(),
    "Invalid total distribution"
  );
}

/**
 * Verify:
 * - initialization params are correctly set
 * - token registration
 */
async function verifyL2Token(
  l2Token: L2ArbitrumToken,
  l1Token: L1ArbitrumToken,
  l2Executor: UpgradeExecutor,
  l2ProxyAdmin: ProxyAdmin,
  arbProvider: Provider,
  ethProvider: Provider,
  config: {
    L2_TOKEN_INITIAL_SUPPLY: string;
    L2_NUM_OF_TOKENS_FOR_TREASURY: string;
    L2_ADDRESS_FOR_FOUNDATION: string;
    L2_NUM_OF_TOKENS_FOR_FOUNDATION: string;
    L2_ADDRESS_FOR_TEAM: string;
    L2_NUM_OF_TOKENS_FOR_TEAM: string;
  }
) {
  //// check ownership
  assertEquals(
    await getProxyOwner(l2Token.address, arbProvider),
    l2ProxyAdmin.address,
    "L2ProxyAdmin should be L2ArbitrumToken's proxy admin"
  );

  //// check initialization params
  assertEquals(await l2Token.name(), "Arbitrum", "L2Token name should be Arbitrum");
  assertEquals(await l2Token.symbol(), "ARB", "L2Token symbol should be ARB");
  assertNumbersEquals(
    await l2Token.totalSupply(),
    ethers.utils.parseEther(config.L2_TOKEN_INITIAL_SUPPLY),
    "L2Token has incorrect total supply"
  );
  assertEquals(
    await l2Token.l1Address(),
    l1Token.address,
    "Incorrect L1Token reference for L2Token"
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
  arbProvider: Provider,
  config: {
    L2_VOTING_DELAY: number;
    L2_VOTING_PERIOD: number;
    L2_PROPOSAL_TRESHOLD: number;
    L2_TREASURY_QUORUM_TRESHOLD: number;
    L2_MIN_PERIOD_AFTER_QUORUM: number;
  }
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
    BigNumber.from(config.L2_VOTING_DELAY),
    "Incorrect voting delay set for L2 treasury governor"
  );
  assertNumbersEquals(
    await l2TreasuryGoverner.votingPeriod(),
    BigNumber.from(config.L2_VOTING_PERIOD),
    "Incorrect voting period set for L2 treasury governor"
  );
  assertNumbersEquals(
    await l2TreasuryGoverner.proposalThreshold(),
    BigNumber.from(config.L2_PROPOSAL_TRESHOLD),
    "Incorrect proposal threshold set for L2 treasury governor"
  );
  assertEquals(
    await l2TreasuryGoverner.token(),
    l2Token.address,
    "Incorrect token set for L2 treasury governor"
  );
  assertNumbersEquals(
    await l2TreasuryGoverner["quorumNumerator()"](),
    BigNumber.from(config.L2_TREASURY_QUORUM_TRESHOLD),
    "Incorrect quorum treshold set for L2 treasury governor"
  );
  assertNumbersEquals(
    await l2TreasuryGoverner.lateQuorumVoteExtension(),
    BigNumber.from(config.L2_MIN_PERIOD_AFTER_QUORUM),
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
  arbProvider: Provider,
  config: {
    L2_TREASURY_TIMELOCK_DELAY: number;
  }
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
    BigNumber.from(config.L2_TREASURY_TIMELOCK_DELAY),
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
export async function verifyL2TokenDistributor(
  l2TokenDistributor: TokenDistributor,
  l2Token: L2ArbitrumToken,
  l2Executor: UpgradeExecutor,
  l2CoreGovernor: L2ArbitrumGovernor,
  arbProvider: Provider,
  claimRecipients: Recipients,
  config: {
    L2_SWEEP_RECEIVER: string;
    L2_CLAIM_PERIOD_START: number;
    L2_CLAIM_PERIOD_END: number;
    GET_LOGS_BLOCK_RANGE: number;
  }
) {
  //// check ownership
  assertEquals(
    await l2TokenDistributor.owner(),
    l2Executor.address,
    "L2UpgradeExecutor should be L2 TokenDistributor's owner"
  );

  //// check token balances
  const recipientTotals = Object.values(claimRecipients).reduce((a, b) => a.add(b));
  assertNumbersEquals(
    await l2Token.balanceOf(l2TokenDistributor.address),
    recipientTotals,
    "Incorrect initial L2Token balance for TokenDistributor"
  );
  assertNumbersEquals(
    await l2TokenDistributor.totalClaimable(),
    recipientTotals,
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
    config.L2_SWEEP_RECEIVER,
    "Incorrect sweep receiver set for TokenDistributor"
  );
  assertNumbersEquals(
    await l2TokenDistributor.claimPeriodStart(),
    BigNumber.from(config.L2_CLAIM_PERIOD_START),
    "Incorrect claim period start set for TokenDistributor"
  );
  assertNumbersEquals(
    await l2TokenDistributor.claimPeriodEnd(),
    BigNumber.from(config.L2_CLAIM_PERIOD_END),
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
 * - Claimant set correctly in token distributor
 */
async function verifyClaimsSetCorrectly(
  l2TokenDistributor: TokenDistributor,
  claimRecipients: Recipients,
  deploymentInfo: {
    distributorSetRecipientsStartBlock: number;
    distributorSetRecipientsEndBlock: number;
  },
  config: {
    GET_LOGS_BLOCK_RANGE: number;
  }
) {
  //// verify that emmited 'CanClaim' events match recipient-amount pairs from file
  const recipientDataFromContract = await getRecipientsDataFromContractEvents(
    l2TokenDistributor,
    Number(deploymentInfo.distributorSetRecipientsStartBlock),
    Number(deploymentInfo.distributorSetRecipientsEndBlock),
    config
  );
  assertNumbersEquals(
    BigNumber.from(Object.keys(recipientDataFromContract).length),
    BigNumber.from(Object.keys(claimRecipients).length),
    "Different number of events emitted compared to number of eligible accounts"
  );
  for (const account in recipientDataFromContract) {
    assertNumbersEquals(
      recipientDataFromContract[account],
      claimRecipients[account],
      "Emitted event data does not match recipient-amount pairs from file"
    );
  }
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

async function verifyArbitrumDAOConstitution(
  arbitrumDAOConstitution: ArbitrumDAOConstitution,
  arbOneUpgradeExecutor: UpgradeExecutor,
  config: {
    ARBITRUM_DAO_CONSTITUTION_HASH: string;
  }
) {
  assertEquals(
    await arbitrumDAOConstitution.owner(),
    arbOneUpgradeExecutor.address,
    "arbOneUpgradeExecutor should be ArbitrumDAOConstitution owner"
  );

  assertEquals(
    await arbitrumDAOConstitution.constitutionHash(),
    config.ARBITRUM_DAO_CONSTITUTION_HASH,
    "Initial constitutionHash should be properly set"
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
  arbProvider: Provider,
  arbOneNetwork: L2Network
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
    arbOneNetwork.tokenBridge.l2GatewayRouter,
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
  novaProvider: Provider,
  config: {
    NOVA_9_OF_12_SECURITY_COUNCIL: string;
  }
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
    await novaUpgradeExecutor.hasRole(executorRole, config.NOVA_9_OF_12_SECURITY_COUNCIL),
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
  novaProvider: Provider,
  ethProvider: Provider,
  novaNetwork: L2Network,
  config: {
    NOVA_TOKEN_NAME: string;
    NOVA_TOKEN_SYMBOL: string;
    NOVA_TOKEN_DECIMALS: number;
  }
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
    config.NOVA_TOKEN_NAME,
    "Incorrect token name set for Nova token"
  );
  assertEquals(
    await novaToken.symbol(),
    config.NOVA_TOKEN_SYMBOL,
    "Incorrect token symbol set on Nova token"
  );
  assertEquals(
    (await novaToken.decimals()).toString(),
    config.NOVA_TOKEN_DECIMALS.toString(),
    "Incorrect token decimals set on Nova token"
  );
  assertEquals(
    await novaToken.l2Gateway(),
    novaNetwork.tokenBridge.l2CustomGateway,
    "Incorrect L2 gateway set on Nova token"
  );
  assertEquals(
    await novaToken.l1Address(),
    l1Token.address,
    "Incorrect L1 token address set on Nova token"
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
 * Verify:
 * - All vested recipients have a vested wallet
 * - Each vested wallet has the recipient balance of tokens
 */
async function verifyVestedWallets(
  vestedRecipients: Recipients,
  vestedWalletFactory: ArbitrumVestingWalletsFactory,
  l2Token: L2ArbitrumToken,
  arbProvider: Provider,
  config: {
    L2_CLAIM_PERIOD_START: number;
  }
) {
  // find all the events emitted by this address
  // check that every recipient has received the correct amount
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
    Object.keys(vestedRecipients).length.toString(),
    "Wallets created number not equal vested recipients number"
  );

  for (const vr of Object.keys(vestedRecipients)) {
    const logs = walletLogs.filter((l) => l.beneficiary.toLowerCase() === vr.toLowerCase());

    assertNumbersEquals(BigNumber.from(logs.length), BigNumber.from(1), "Too many logs");

    const log = logs[0];
    const tokenBalance = await l2Token.balanceOf(log.vestingWalletAddress);

    assertNumbersEquals(
      vestedRecipients[vr],
      tokenBalance,
      "Recipient amount not equal token balance"
    );

    const vestingWallet = ArbitrumVestingWallet__factory.connect(
      log.vestingWalletAddress,
      arbProvider
    );
    const oneYearInSeconds = 365 * 24 * 60 * 60;

    const start = await vestingWallet.start();
    assertNumbersEquals(
      start,
      BigNumber.from(config.L2_CLAIM_PERIOD_START + oneYearInSeconds),
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

export async function getInitialSupplyRecipientAddr(
  arbProvider: Provider,
  l2Token: L2ArbitrumToken
) {
  // find the initial supply recipient - this is the arb deployer
  // use index = 1 because
  // the first transfer is to the contract deployer from 0 address
  // the second transfer is to the owner AKA the intiial supply recipient
  // the third transfer is to the upgrade executor
  const initialSupplyRecipient = (
    await arbProvider.getLogs({
      ...l2Token.filters.OwnershipTransferred(),
      fromBlock: 0,
      toBlock: "latest",
    })
  )
    .sort((a, b) => a.blockNumber - b.blockNumber)
    .map(
      (l) => l2Token.interface.parseLog(l).args as OwnershipTransferredEvent["args"]
    )[1].newOwner;

  return initialSupplyRecipient;
}

/**
 * Verify:
 * - All dao recipients recieved a transfer of the correct amount
 */
export async function verifyDaoRecipients(
  initialSupplyRecipientAddress: string,
  daoRecipients: Recipients,
  l2Token: L2ArbitrumToken,
  arbProvider: Provider
) {
  for (const dr of Object.keys(daoRecipients)) {
    const filter = l2Token.filters["Transfer(address,address,uint256)"](
      initialSupplyRecipientAddress,
      dr
    );

    const transferLogs = (
      await arbProvider.getLogs({
        ...filter,
        fromBlock: 0,
        toBlock: "latest",
      })
    ).map((l) => {
      return l2Token.interface.parseLog(l).args as TransferEvent["args"];
    });

    assertNumbersEquals(
      BigNumber.from(transferLogs.length),
      BigNumber.from(1),
      `Too many logs: ${transferLogs}`
    );

    const tLog = transferLogs[0];
    const tokenBalance = await l2Token.balanceOf(tLog.to);

    assertNumbersEquals(
      daoRecipients[dr],
      tokenBalance,
      "Dao recipient amount not equal token balance"
    );
  }
}

/**
 *
 * @param ethProvider
 * @returns
 */
export function loadL1Contracts(ethProvider: Provider, contractAddresses: DeployProgressCache) {
  if (contractAddresses.l1GovernanceFactory == undefined)
    throw new Error("Missing l1GovernanceFactory");
  if (contractAddresses.l1TokenProxy == undefined) throw new Error("Missing l1TokenProxy");
  if (contractAddresses.l1Executor == undefined) throw new Error("Missing l1Executor");
  if (contractAddresses.l1Timelock == undefined) throw new Error("Missing l1Timelock");
  if (contractAddresses.l1ProxyAdmin == undefined) throw new Error("Missing l1ProxyAdmin");
  if (contractAddresses.l1ReverseCustomGatewayProxy == undefined)
    throw new Error("Missing l1ReverseCustomGatewayProxy");
  return {
    // load L1 contracts
    l1GovernanceFactory: L1GovernanceFactory__factory.connect(
      contractAddresses["l1GovernanceFactory"],
      ethProvider
    ),
    l1TokenProxy: L1ArbitrumToken__factory.connect(contractAddresses["l1TokenProxy"], ethProvider),
    l1Executor: UpgradeExecutor__factory.connect(contractAddresses["l1Executor"], ethProvider),
    l1Timelock: L1ArbitrumTimelock__factory.connect(contractAddresses["l1Timelock"], ethProvider),
    l1ProxyAdmin: ProxyAdmin__factory.connect(contractAddresses["l1ProxyAdmin"], ethProvider),
    l1ReverseCustomGatewayProxy: L1ForceOnlyReverseCustomGateway__factory.connect(
      contractAddresses["l1ReverseCustomGatewayProxy"],
      ethProvider
    ),
  };
}

/**
 *
 * @param arbProvider
 * @returns
 */
export function loadArbContracts(arbProvider: Provider, contractAddresses: DeployProgressCache) {
  if (contractAddresses.l2Token == undefined) throw new Error("Missing l2Token");
  if (contractAddresses.l2Executor == undefined) throw new Error("Missing l2Executor");
  if (contractAddresses.l2GovernanceFactory == undefined)
    throw new Error("Missing l2GovernanceFactory");
  if (contractAddresses.l2CoreGoverner == undefined) throw new Error("Missing l2CoreGoverner");
  if (contractAddresses.l2CoreTimelock == undefined) throw new Error("Missing l2CoreTimelock");
  if (contractAddresses.l2ProxyAdmin == undefined) throw new Error("Missing l2ProxyAdmin");
  if (contractAddresses.l2TreasuryGoverner == undefined)
    throw new Error("Missing l2TreasuryGoverner");
  if (contractAddresses.l2ArbTreasury == undefined) throw new Error("Missing l2ArbTreasury");
  if (contractAddresses.l2ReverseCustomGatewayProxy == undefined)
    throw new Error("Missing l2ReverseCustomGatewayProxy");
  if (contractAddresses.arbitrumDAOConstitution == undefined)
    throw new Error("Missing arbitrumDAOConstitution");

  return {
    // load L2 contracts
    l2Token: L2ArbitrumToken__factory.connect(contractAddresses.l2Token, arbProvider),
    l2Executor: UpgradeExecutor__factory.connect(contractAddresses["l2Executor"], arbProvider),
    l2GovernanceFactory: L2GovernanceFactory__factory.connect(
      contractAddresses.l2GovernanceFactory,
      arbProvider
    ),
    l2CoreGoverner: L2ArbitrumGovernor__factory.connect(
      contractAddresses.l2CoreGoverner,
      arbProvider
    ),
    l2CoreTimelock: ArbitrumTimelock__factory.connect(
      contractAddresses.l2CoreTimelock,
      arbProvider
    ),
    l2ProxyAdmin: ProxyAdmin__factory.connect(contractAddresses.l2ProxyAdmin, arbProvider),
    l2TreasuryGoverner: L2ArbitrumGovernor__factory.connect(
      contractAddresses.l2TreasuryGoverner,
      arbProvider
    ),
    l2ArbTreasury: FixedDelegateErc20Wallet__factory.connect(
      contractAddresses.l2ArbTreasury,
      arbProvider
    ),
    l2ReverseCustomGatewayProxy: L2ReverseCustomGateway__factory.connect(
      contractAddresses.l2ReverseCustomGatewayProxy,
      arbProvider
    ),
    arbitrumDAOConstitution: ArbitrumDAOConstitution__factory.connect(
      contractAddresses.arbitrumDAOConstitution,
      arbProvider
    ),
  };
}

/**
 *
 * @param arbProvider
 * @returns
 */
export function loadArbTokenDistributor(
  arbProvider: Provider,
  contractAddresses: DeployProgressCache
) {
  if (contractAddresses.l2TokenDistributor == undefined)
    throw new Error("Missing l2TokenDistributor");

  return TokenDistributor__factory.connect(contractAddresses.l2TokenDistributor, arbProvider);
}

/**
 *
 * @param arbProvider
 * @returns
 */
export function loadVestedWalletFactory(
  arbProvider: Provider,
  contractAddresses: DeployProgressCache
) {
  if (contractAddresses.vestedWalletFactory == undefined)
    throw new Error("Missing vestedWalletFactory");

  return ArbitrumVestingWalletsFactory__factory.connect(
    contractAddresses.vestedWalletFactory,
    arbProvider
  );
}

/**
 * Sanity check token supply totals
 * @param config
 */
export function checkConfigTotals(
  claimRecipients: Recipients,
  config: {
    L2_TOKEN_INITIAL_SUPPLY: string;
    L2_NUM_OF_TOKENS_FOR_TREASURY: string;
    L2_NUM_OF_TOKENS_FOR_FOUNDATION: string;
    L2_NUM_OF_TOKENS_FOR_TEAM: string;
    L2_NUM_OF_TOKENS_FOR_DAO_RECIPIENTS: string;
    L2_NUM_OF_TOKENS_FOR_INVESTORS: string;
  }
) {
  const totalSupply = parseEther(config.L2_TOKEN_INITIAL_SUPPLY);
  const treasuryVal = parseEther(config.L2_NUM_OF_TOKENS_FOR_TREASURY);
  const foundationVal = parseEther(config.L2_NUM_OF_TOKENS_FOR_FOUNDATION);
  const teamVal = parseEther(config.L2_NUM_OF_TOKENS_FOR_TEAM);
  const daoVal = parseEther(config.L2_NUM_OF_TOKENS_FOR_DAO_RECIPIENTS);
  const investorVal = parseEther(config.L2_NUM_OF_TOKENS_FOR_INVESTORS);

  const claimtotal = Object.values(claimRecipients).reduce((a, b) => a.add(b));

  const distributionTotals = treasuryVal
    .add(foundationVal)
    .add(teamVal)
    .add(claimtotal)
    .add(investorVal)
    .add(daoVal);
  if (!distributionTotals.eq(totalSupply)) {
    throw new Error(
      `Unexpected distribution total: ${distributionTotals.toString()} ${totalSupply.toString()}`
    );
  }
}

/**
 *
 * @param novaProvider
 * @returns
 */
export function loadNovaContracts(novaProvider: Provider, contractAddresses: DeployProgressCache) {
  if (contractAddresses.novaProxyAdmin == undefined) throw new Error("Missing novaProxyAdmin");
  if (contractAddresses.novaUpgradeExecutorProxy == undefined)
    throw new Error("Missing novaUpgradeExecutorProxy");
  if (contractAddresses.novaTokenProxy == undefined) throw new Error("Missing novaTokenProxy");

  return {
    // load Nova contracts
    novaProxyAdmin: ProxyAdmin__factory.connect(contractAddresses["novaProxyAdmin"], novaProvider),
    novaUpgradeExecutorProxy: UpgradeExecutor__factory.connect(
      contractAddresses.novaUpgradeExecutorProxy,
      novaProvider
    ),
    novaTokenProxy: L2CustomGatewayToken__factory.connect(
      contractAddresses.novaTokenProxy,
      novaProvider
    ),
  };
}
