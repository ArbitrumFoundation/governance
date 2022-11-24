//// L1
// minimum delay for an operation to become valid
export const L1_TIMELOCK_DELAY = 5;
// 9/12 security council can perform emergency upgrades (dummy value atm)
export const L1_9_OF_12_SECURITY_COUNCIL = "0x76CDc6DB8333cBa9E6d710163eb82DD906893fDa";
// arb one router
export const L1_ARB_ROUTER = "0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef";
// arb one erc20 gateway
export const L1_ARB_GATEWAY = "0xa3A7B6F88361F48403514059F1F16C8E78d60EeC";
// nova router
export const L1_NOVA_ROUTER = "0xC840838Bc438d73C16c2f8b22D2Ce3669963cD48";
// nova gateway
export const L1_NOVA_GATEWAY = "0xB2535b988dcE19f9D71dfB22dB6da744aCac21bf";
// Arbitrum inbox on L1 (local network value atm)
export const L1_ARB_INBOX = "0xf5f495a108acc0b75b9a532f2f28836d7f059b8b";

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
export const NOVA_TOKEN_GATEWAY = "0xb19DAC9ab07f9ee2F8002446De0bCA04e44Ec3D9";

//// L2 Arbitrum token
// 10 billion tokens (we use parseEther in script to add decimals)
export const L2_TOKEN_INITIAL_SUPPLY = "10000000000";
// 2 billion tokens (dummy value atm)
export const L2_NUM_OF_TOKENS_FOR_TREASURY = "2000000000";
// receiver of the airdrop leftovers (dummy value atm)
export const L2_SWEEP_RECECIVER = "0x0B563dfac4940547D04f6B58D719B5AA2e29597d";
// initial owner responsible for setting the airdrop recipients (dummy value atm)
export const L2_TOKEN_DISTRIBUTOR_OWNER = "0x59D74CC054A520217D6eC7eAED6C36507347A236";
// airdrop claim start block number (dummy value atm)
export const L2_CLAIM_PERIOD_START = 16100000;
// airdrop claim end block number (dummy value atm)
export const L2_CLAIM_PERIOD_END = 16200000;
