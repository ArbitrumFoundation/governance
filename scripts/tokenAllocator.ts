import { Contract, Signer } from "ethers";
import { parseEther } from "ethers/lib/utils";
import {
  L2ArbitrumGovernor__factory,
  L2ArbitrumToken__factory,
  TokenDistributor,
  TokenDistributor__factory,
} from "../typechain-types";

import {
  DeployProgressCache,
  getDeployersAndConfig as getDeployersAndConfig,
  loadDeployedContracts,
  updateDeployedContracts,
} from "./providerSetup";
import { getRecipientsDataFromContractEvents, setClaimRecipients } from "./tokenDistributorHelper";
import { deployVestedWallets } from "./vestedWalletsDeployer";
import { Recipients, StringProps, TypeChainContractFactoryStatic } from "./testUtils";
import { checkConfigTotals } from "./verifiers";

// use a global cache
let deployedContracts: DeployProgressCache = {};

/**
 * /// 15. Post deployment L2 tasks - transfer tokens
 * ///         - transfer L2 token ownership to upgradeExecutor
 * ///         - transfer part of tokens to treasury
 * ///         - transfer part of tokens to foundation
 * ///         - transfer part of tokens to team
 * /// 16. Distribute to vested wallets
 * ///         - create vested wallets
 * ///         - transfer funds to vested wallets
 * /// 17. Deploy TokenDistributor
 * ///         - deploy TokenDistributor
 * ///         - transfer claimable tokens from arbDeployer to distributor
 * /// 18. Write addresses of deployed contracts to local JSON file
 * /// 19. Init TokenDistributor
 * ///         - set claim recipients (done in batches over ~2h period)
 * ///         - if number of set recipients and total claimable amount match expected values, transfer ownership to executor
 */
export const allocateTokens = async () => {
  console.log("Get deployers and signers");
  const { arbDeployer, deployerConfig, claimRecipients } = await getDeployersAndConfig();

  // sanity check the token totals before we start the deployment
  checkConfigTotals(claimRecipients, deployerConfig);

  console.log("Post deployment L2 token tasks");
  await postDeploymentL2TokenTasks(
    arbDeployer,
    deployedContracts.l2Token!,
    deployedContracts.l2Executor!,
    deployedContracts.l2ArbTreasury!,
    deployerConfig
  );

  // deploy ARB distributor
  console.log("Deploy TokenDistributor");
  const tokenDistributor = await deployTokenDistributor(
    arbDeployer,
    deployedContracts.l2Token!,
    deployedContracts.l2CoreGoverner!,
    arbDeployer,
    claimRecipients,
    deployerConfig
  );

  // write addresses before the last step which takes hours
  console.log("Write deployed contract addresses to deployedContracts.json");
  updateDeployedContracts(deployedContracts);

  console.log("Set TokenDistributor recipients");
  await initTokenDistributor(
    tokenDistributor,
    arbDeployer,
    deployedContracts.l2Executor!,
    claimRecipients,
    deployerConfig
  );
};

async function postDeploymentL2TokenTasks(
  arbInitialSupplyRecipient: Signer,
  l2TokenAddress: string,
  l2ExecutorAddress: string,
  arbTreasuryAddress: string,
  config: {
    L2_NUM_OF_TOKENS_FOR_TREASURY: string;
    L2_ADDRESS_FOR_FOUNDATION: string;
    L2_NUM_OF_TOKENS_FOR_FOUNDATION: string;
    L2_ADDRESS_FOR_TEAM: string;
    L2_NUM_OF_TOKENS_FOR_TEAM: string;
    L2_ADDRESS_FOR_DAO_RECIPIENTS: string;
    L2_NUM_OF_TOKENS_FOR_DAO_RECIPIENTS: string;
    L2_ADDRESS_FOR_INVESTORS: string;
    L2_NUM_OF_TOKENS_FOR_INVESTORS: string;
  }
) {
  const l2Token = L2ArbitrumToken__factory.connect(l2TokenAddress, arbInitialSupplyRecipient);
  if (!deployedContracts.l2TokenTask1) {
    // transfer L2 token ownership to upgradeExecutor

    await (await l2Token.transferOwnership(l2ExecutorAddress)).wait();

    deployedContracts.l2TokenTask1 = true;
  }

  if (!deployedContracts.l2TokenTask2) {
    // transfer tokens from arbDeployer to the treasury
    await (
      await l2Token.transfer(arbTreasuryAddress, parseEther(config.L2_NUM_OF_TOKENS_FOR_TREASURY))
    ).wait();

    deployedContracts.l2TokenTask2 = true;
  }

  if (!deployedContracts.l2TokenTask3) {
    // transfer tokens from arbDeployer to the foundation
    await (
      await l2Token.transfer(
        config.L2_ADDRESS_FOR_FOUNDATION,
        parseEther(config.L2_NUM_OF_TOKENS_FOR_FOUNDATION)
      )
    ).wait();

    deployedContracts.l2TokenTask3 = true;
  }

  if (!deployedContracts.l2TokenTask4) {
    // transfer tokens from arbDeployer to the team
    await (
      await l2Token.transfer(
        config.L2_ADDRESS_FOR_TEAM,
        parseEther(config.L2_NUM_OF_TOKENS_FOR_TEAM)
      )
    ).wait();

    deployedContracts.l2TokenTask4 = true;
  }

  if (!deployedContracts.l2TokenTask5) {
    // transfer tokens from arbDeployer to the dao recipients escrow
    await (
      await l2Token.transfer(
        config.L2_ADDRESS_FOR_DAO_RECIPIENTS,
        parseEther(config.L2_NUM_OF_TOKENS_FOR_DAO_RECIPIENTS)
      )
    ).wait();

    deployedContracts.l2TokenTask5 = true;
  }

  if (!deployedContracts.l2TokenTask6) {
    // transfer tokens from arbDeployer to the investor escrow
    await (
      await l2Token.transfer(
        config.L2_ADDRESS_FOR_INVESTORS,
        parseEther(config.L2_NUM_OF_TOKENS_FOR_INVESTORS)
      )
    ).wait();

    deployedContracts.l2TokenTask6 = true;
  }
}

async function deployAndTransferVestedWallets(
  arbDeployer: Signer,
  arbInitialSupplyRecipient: Signer,
  l2TokenAddress: string,
  vestedRecipients: Recipients,
  config: {
    L2_CLAIM_PERIOD_START: number;
  }
) {
  const oneYearInSeconds = 365 * 24 * 60 * 60;

  if (!deployedContracts.vestedWalletFactory) {
    // we dont currently have full error handling for errors thrown during
    // vested wallet deployment, for now just throw an error and require
    // manual intervention if an error occurs in here
    if (deployedContracts.vestedWalletInProgress) {
      throw new Error(
        "Vested wallet deployment started but a failure occurred, manual intervention required"
      );
    }
    deployedContracts.vestedWalletInProgress = true;

    const vestedWalletFactory = await deployVestedWallets(
      arbDeployer,
      arbInitialSupplyRecipient,
      l2TokenAddress,
      vestedRecipients,
      // start vesting in 1 years time
      config.L2_CLAIM_PERIOD_START + oneYearInSeconds,
      // vesting lasts for 3 years
      oneYearInSeconds * 3
    );
    deployedContracts.vestedWalletInProgress = undefined;
    deployedContracts.vestedWalletFactory = vestedWalletFactory.address;
  }
}

async function deployTokenDistributor(
  arbDeployer: Signer,
  l2TokenAddress: string,
  l2CoreGovernerAddress: string,
  arbInitialSupplyRecipient: Signer,
  claimRecipients: Recipients,
  config: {
    L2_SWEEP_RECEIVER: string;
    L2_CLAIM_PERIOD_START: number;
    L2_CLAIM_PERIOD_END: number;
  }
): Promise<TokenDistributor> {
  // deploy TokenDistributor
  const delegationExcludeAddress = await L2ArbitrumGovernor__factory.connect(
    l2CoreGovernerAddress,
    arbDeployer
  ).EXCLUDE_ADDRESS();

  const tokenDistributor = await getOrInit(
    "l2TokenDistributor",
    arbDeployer,
    TokenDistributor__factory,
    async () => {
      return await new TokenDistributor__factory(arbDeployer).deploy(
        l2TokenAddress,
        config.L2_SWEEP_RECEIVER,
        await arbDeployer.getAddress(),
        config.L2_CLAIM_PERIOD_START,
        config.L2_CLAIM_PERIOD_END,
        delegationExcludeAddress
      );
    }
  );

  if (!deployedContracts.l2TokenTransferTokenDistributor) {
    // transfer tokens from arbDeployer to the distributor
    const l2Token = L2ArbitrumToken__factory.connect(l2TokenAddress, arbInitialSupplyRecipient);
    const recipientTotal = Object.values(claimRecipients).reduce((a, b) => a.add(b));
    await (await l2Token.transfer(tokenDistributor.address, recipientTotal)).wait();

    deployedContracts.l2TokenTransferTokenDistributor = true;
  }

  return tokenDistributor;
}

async function initTokenDistributor(
  tokenDistributor: TokenDistributor,
  arbDeployer: Signer,
  l2ExecutorAddress: string,
  claimRecipients: Recipients,
  config: {
    RECIPIENTS_BATCH_SIZE: number;
    BASE_L2_GAS_PRICE_LIMIT: number;
    BASE_L1_GAS_PRICE_LIMIT: number;
    GET_LOGS_BLOCK_RANGE: number;
  }
) {
  // we store start block when recipient batches are being set
  const previousStartBlock = deployedContracts.distributorSetRecipientsStartBlock;
  if (deployedContracts.distributorSetRecipientsStartBlock == undefined) {
    // store the start block in case we fail
    deployedContracts.distributorSetRecipientsStartBlock =
      await arbDeployer.provider!.getBlockNumber();
  }

  // make sure setClaimRecipients is successfully executed (even in case of intermittent RPC timeout or similar)
  while (true) {
    try {
      // set claim recipients
      await setClaimRecipients(
        tokenDistributor,
        arbDeployer,
        claimRecipients,
        config,
        previousStartBlock
      );
      console.log("Recipients successfully set!");
      break;
    } catch (err) {
      console.error("Setting recipients threw exception, retrying after 30sec...", err);
      await new Promise((resolve) => setTimeout(resolve, 30000));
    }
  }

  // we store end block when all recipients batches are set
  deployedContracts.distributorSetRecipientsEndBlock = await arbDeployer.provider!.getBlockNumber();

  const blockNow = await arbDeployer.provider!.getBlockNumber();
  const numOfRecipientsSet = Object.keys(
    await getRecipientsDataFromContractEvents(
      tokenDistributor,
      previousStartBlock || 0,
      blockNow,
      config
    )
  ).length;

  // check num of recipients and claimable amount before transferring ownership
  const totalClaimable = await tokenDistributor.totalClaimable();

  const recipientTotals = Object.values(claimRecipients).reduce((a, b) => a.add(b));

  if (!totalClaimable.eq(recipientTotals)) {
    throw new Error("Incorrect totalClaimable amount of tokenDistributor: " + totalClaimable);
  }
  if (numOfRecipientsSet != Object.keys(claimRecipients).length) {
    throw new Error(
      `Incorrect number of recipients set: ${numOfRecipientsSet}/${
        Object.keys(claimRecipients).length
      }`
    );
  }

  if (!deployedContracts.l2TokenTransferOwnership) {
    // transfer ownership to L2 UpgradeExecutor
    await (await tokenDistributor.transferOwnership(l2ExecutorAddress)).wait();
    deployedContracts.l2TokenTransferOwnership = true;
  }
}

async function getOrInit<TContract extends Contract>(
  cacheKey: keyof StringProps<DeployProgressCache>,
  deployer: Signer,
  contractFactory: TypeChainContractFactoryStatic<TContract>,
  deploy: () => Promise<TContract>
): Promise<TContract> {
  const address = deployedContracts[cacheKey];
  if (!address) {
    const contract = await deploy();
    await contract.deployed();
    deployedContracts[cacheKey] = contract.address;
    return contract;
  } else {
    return contractFactory.connect(address, deployer);
  }
}

async function main() {
  console.log("Start token allocation process...");
  deployedContracts = loadDeployedContracts();
  console.log(`Cache: ${JSON.stringify(deployedContracts, null, 2)}`);
  try {
    await allocateTokens();
  } finally {
    // write addresses of deployed contracts even when exception is thrown
    console.log("Write deployed contract addresses to deployedContracts.json");
    updateDeployedContracts(deployedContracts);
  }
  console.log("Allocation finished!");
}

main().then(() => console.log("Done."));
