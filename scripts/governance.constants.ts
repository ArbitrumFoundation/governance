//// L1
// minimum delay for an operation to become valid
export const L1_TIMELOCK_DELAY = 5;
// 9/12 security council can perform emergency upgrades (dummy value atm)
export const L1_9_OF_12_SECURITY_COUNCIL = "0x76CDc6DB8333cBa9E6d710163eb82DD906893fDa";
// arb one router (local network value atm)
export const L1_ARB_ROUTER = "0x90619A5690CEA8514b0CebB8B3c004Cb2Bc15d6e";
// arb one custom gateway (local network value atm)
export const L1_ARB_GATEWAY = "0xFb9d427F048676563CFa57651803587c4bC9D699";
// Arbitrum inbox on L1 (local network value atm)
export const L1_ARB_INBOX = "0x0409127Aa3E66fC4A0E204f7B1D7ABb047640484";
// nova router (local network value atm (local network value atm from localNetworkNova.json))
export const L1_NOVA_ROUTER = "0x7b4976f0F0614d9e1E808A33958aa9CEBA5646B9";
// nova custom gateway (local network value atm from localNetworkNova.json)
export const L1_NOVA_GATEWAY = "0x2e343C93ea73cdB0f495402d350b97C2A1F80529";

//// L2
// minimum delay for an operation to become valid (dummy value atm)
export const L2_TIMELOCK_DELAY = 7;
// 9/12 security council can perform emergency upgrades (dummy value atm)
export const L2_9_OF_12_SECURITY_COUNCIL = "0xD99DD65559341008213A41E17e29777872bab481";
// 7/12 security council can schedule proposals (dummy value atm)
export const L2_7_OF_12_SECURITY_COUNCIL = "0xFde71E607Fa694284F21F620ac2720291614FaCe";
// proportion of the circulating supply required to reach a quorum (dummy value atm)
export const L2_CORE_QUORUM_TRESHOLD = 5;
// proportion of the circulating supply required to reach a quorum (dummy value atm)
export const L2_TREASURY_QUORUM_TRESHOLD = 3;
// the number of votes required in order for a voter to become a proposer (dummy value atm)
export const L2_PROPOSAL_TRESHOLD = 100;
// delay (in number of blocks) since the proposal is submitted until voting power is fixed and voting starts (dummy value atm)
export const L2_VOTING_DELAY = 10;
// delay (in number of blocks) since the proposal starts until voting ends (dummy value atm)
export const L2_VOTING_PERIOD = 10;
// the number of blocks that are required to pass since a proposal reaches quorum until its voting period ends (dummy value atm)
export const L2_MIN_PERIOD_AFTER_QUORUM = 1;

//// Nova
// 9/12 security council can perform emergency upgrades (dummy value atm)
export const NOVA_9_OF_12_SECURITY_COUNCIL = "0xB3594078bFab918F022f8cD90721a543E39083D7";
export const NOVA_TOKEN_NAME = "Arbitrum";
export const NOVA_TOKEN_SYMBOL = "ARB";
export const NOVA_TOKEN_DECIMALS = 18;
// token gateway on Nova (dummy value at (local network value atm from localNetworkNova.json)m)
export const NOVA_TOKEN_GATEWAY = "0x206a8a5BfA589552A2e5569a6D0c2ab284d75494";

//// L2 Arbitrum token
// 10 billion tokens (we use parseEther in script to add decimals)
export const L2_TOKEN_INITIAL_SUPPLY = "10000000000";
// 8 billion tokens (dummy value atm)
export const L2_NUM_OF_TOKENS_FOR_TREASURY = "8000000000";
// ~2 billion tokens (based on sum of claimable tokens in JSON file)
export const L2_NUM_OF_TOKENS_FOR_CLAIMING = "48000";
// receiver of the airdrop leftovers (dummy value atm)
export const L2_SWEEP_RECECIVER = "0x0B563dfac4940547D04f6B58D719B5AA2e29597d";
// airdrop claim start block number (dummy value atm)
export const L2_CLAIM_PERIOD_START = 16100000;
// airdrop claim end block number (dummy value atm)
export const L2_CLAIM_PERIOD_END = 16200000;
// total number of airdrop recipients (dummy value atm)
export const L2_NUM_OF_RECIPIENTS = 4;
// num of airdrop recipient batches that were successfully set, by default 0. If deployer script fails
// while setting recipient batches, this value can be updated so in the next run deployer scripts continues
// setting recipients from the right batch (where it failed the last time)
export const L2_NUM_OF_RECIPIENT_BATCHES_ALREADY_SET = 0;
// router on ARB L2 (local network value atm)
export const L2_GATEWAY_ROUTER = "0x76998688606cBDBaaeC22f45AF549e7519Fa642D";
