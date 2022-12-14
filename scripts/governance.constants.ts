//// L1
// minimum delay for an operation to become valid
export const L1_TIMELOCK_DELAY = 900; // 15 min
// 9/12 security council can perform emergency upgrades
export const L1_9_OF_12_SECURITY_COUNCIL = "0xf9d5ae34E9A552e42c1d7CE268D23C9eb35ED62d";
// arb one router
export const L1_ARB_ROUTER = "0x90619A5690CEA8514b0CebB8B3c004Cb2Bc15d6e";
// Arbitrum inbox on L1
export const L1_ARB_INBOX = "0x1f59DbA2d174E5a2611992AE445432638Cc72C63";
// nova router
export const L1_NOVA_ROUTER = "0xe25777eEBD8A03cE0A2fE4B790AC7C9A9D66dacD";
// nova custom gateway
export const L1_NOVA_GATEWAY = "0xE5b30660cC2c1204dE8d44ed61c6f60B92356F29";

//// L2
// minimum delay for an operation to become valid (dummy value atm)
export const L2_TIMELOCK_DELAY = 900; // 15 min
// 9/12 security council can perform emergency upgrades
export const L2_9_OF_12_SECURITY_COUNCIL = "0x68357c0F94c1D71EDFB829CB01e7f4252897c14B";
// 7/12 security council can schedule proposals
export const L2_7_OF_12_SECURITY_COUNCIL = "0x9AcD891CFFA39f547bb3e271326f775a1fE76964";
// proportion of the circulating supply required to reach a quorum
export const L2_CORE_QUORUM_TRESHOLD = 5;
// proportion of the circulating supply required to reach a quorum
export const L2_TREASURY_QUORUM_TRESHOLD = 3;
// the number of votes required in order for a voter to become a proposer
export const L2_PROPOSAL_TRESHOLD = 100;
// delay (in number of blocks) since the proposal is submitted until voting power is fixed and voting starts
export const L2_VOTING_DELAY = 900; // 15min with 1s L1 blocktime
// delay (in number of blocks) since the proposal starts until voting ends
export const L2_VOTING_PERIOD = 3600; // 60min with 1s L1 blocktime
// the number of blocks that are required to pass since a proposal reaches quorum until its voting period ends
export const L2_MIN_PERIOD_AFTER_QUORUM = 900; // 15min with 1s L1 blocktime

//// Nova
// 9/12 security council can perform emergency upgrades
export const NOVA_9_OF_12_SECURITY_COUNCIL = "0x210902136F8E9dE360E006c5BBA3e9e66aaaBea2";
export const NOVA_TOKEN_NAME = "Arbitrum";
export const NOVA_TOKEN_SYMBOL = "ARB";
export const NOVA_TOKEN_DECIMALS = 18;
// custom token gateway on Nova
export const NOVA_TOKEN_GATEWAY = "0x28B3a95f8e6508dc2C0097Ac543C8B2eFff21bF9";

//// L2 Arbitrum token
// 10 billion tokens (we use parseEther in script to add decimals)
export const L2_TOKEN_INITIAL_SUPPLY = "10000000000";
// num of tokens to be sent to treasury (total - distributor tokens)
export const L2_NUM_OF_TOKENS_FOR_TREASURY = "8144087500";
// num of tokens to be sent to distributor (based on sum of claimable tokens in JSON file)
export const L2_NUM_OF_TOKENS_FOR_CLAIMING = "1855912500";
// receiver of the airdrop leftovers
export const L2_SWEEP_RECECIVER = "0x3931dFcf7D4075742eA650b323b27837b52d816D";
// airdrop claim start block number
export const L2_CLAIM_PERIOD_START = 59702;
// airdrop claim end block number
export const L2_CLAIM_PERIOD_END = 1874102;
// total number of airdrop recipients
export const L2_NUM_OF_RECIPIENTS = 300007;
// num of airdrop recipient batches that were successfully set, by default 0. If deployer script fails
// while setting recipient batches, this value can be updated so in the next run deployer scripts continues
// setting recipients from the right batch (where it failed the last time)
export const L2_NUM_OF_RECIPIENT_BATCHES_ALREADY_SET = 0;
// router on ARB L2
export const L2_GATEWAY_ROUTER = "0x76998688606cBDBaaeC22f45AF549e7519Fa642D";
