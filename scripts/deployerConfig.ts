import fs from "fs";

/**
 * Config required in order to run the governance deployer
 */
export interface DeployerConfig {
  //////////////
  ///// L1 /////
  //////////////
  /**
   * Minimum delay for an operation to become valid
   */
  L1_TIMELOCK_DELAY: number;
  /**
   * 9/12 security council can perform emergency upgrades
   */
  L1_9_OF_12_SECURITY_COUNCIL: string;

  //////////////
  ///// L2 /////
  //////////////
  /**
   * Minimum delay for an operation to become valid
   */
  L2_TIMELOCK_DELAY: number;
  /**
   * 9/12 security council can perform emergency upgrades
   */
  L2_9_OF_12_SECURITY_COUNCIL: string;
  /**
   * 7/12 security council can schedule proposals
   */
  L2_7_OF_12_SECURITY_COUNCIL: string;
  /**
   * Proportion of the circulating supply required to reach a quorum
   */
  L2_CORE_QUORUM_TRESHOLD: number;
  /**
   * Proportion of the circulating supply required to reach a quorum
   */
  L2_TREASURY_QUORUM_TRESHOLD: number;
  /**
   * The number of votes required in order for a voter to become a proposer
   */
  L2_PROPOSAL_TRESHOLD: number;
  /**
   * Delay (in number of blocks) since the proposal is submitted until voting power is fixed and voting starts
   */
  L2_VOTING_DELAY: number;
  /**
   * Delay (in number of blocks) since the proposal starts until voting ends
   */
  L2_VOTING_PERIOD: number;
  /**
   * The number of blocks that are required to pass since a proposal reaches quorum until its voting period ends
   */
  L2_MIN_PERIOD_AFTER_QUORUM: number;

  ////////////////
  ///// Nova /////
  ////////////////
  /**
   * 9/12 security council can perform emergency upgrades
   */
  NOVA_9_OF_12_SECURITY_COUNCIL: string;
  NOVA_TOKEN_NAME: string;
  NOVA_TOKEN_SYMBOL: string;
  NOVA_TOKEN_DECIMALS: number;

  ////////////////////////
  ///// L2 Arb Token /////
  ////////////////////////
  /**
   * 10 billion tokens (we use parseEther in script to add decimals)
   */
  L2_TOKEN_INITIAL_SUPPLY: string;
  /**
   * Num of tokens to be sent to treasury
   */
  L2_NUM_OF_TOKENS_FOR_TREASURY: string;
  /**
   * Num of tokens to be sent to distributor (based on sum of claimable tokens in JSON file)
   */
  L2_NUM_OF_TOKENS_FOR_CLAIMING: string;
  /**
   * Receiver of the airdrop leftovers
   */
  L2_SWEEP_RECEIVER: string;
  /**
   * Airdrop claim start block number
   */
  L2_CLAIM_PERIOD_START: number;
  /**
   * Airdrop claim end block number
   */
  L2_CLAIM_PERIOD_END: number;
  /**
   * Total number of airdrop recipients
   */
  L2_NUM_OF_RECIPIENTS: number;
  /**
   * Batch size when setting the airdrop recipients in token distributor
   */
  RECIPIENTS_BATCH_SIZE: number;
  /**
   * Base Arb gas price of 0.1 gwei
   */
  BASE_L2_GAS_PRICE_LIMIT: number;
  /**
   * Acceptable upper limit for L1 gas price
   */
  BASE_L1_GAS_PRICE_LIMIT: number;
  /**
   * Block range for eth_getLogs calls
   */
  GET_LOGS_BLOCK_RANGE: number;
  /**
   * Keccak256 hash of the  initial (i.e., at deploy time) constitution text
   */
  ARBITRUM_DAO_CONSTITUTION_HASH: string;
}

export const loadDeployerConfig = async (fileLocation: string) => {
  return JSON.parse(fs.readFileSync(fileLocation).toString()) as DeployerConfig;
};
