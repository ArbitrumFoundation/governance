//// L1
export const L1_TIMELOCK_DELAY = 5;
export const L1_9_OF_12_SECURITY_COUNCIL = "0x76CDc6DB8333cBa9E6d710163eb82DD906893fDa";
export const L1_ARB_ROUTER = "0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef";
export const L1_ARB_GATEWAY = "0xa3A7B6F88361F48403514059F1F16C8E78d60EeC";
export const L1_NOVA_ROUTER = "0xC840838Bc438d73C16c2f8b22D2Ce3669963cD48";
export const L1_NOVA_GATEWAY = "0xB2535b988dcE19f9D71dfB22dB6da744aCac21bf";

//// L2
export const L2_TIMELOCK_DELAY = 7; 
export const L2_9_OF_12_SECURITY_COUNCIL = "0xD99DD65559341008213A41E17e29777872bab481";
export const L2_7_OF_12_SECURITY_COUNCIL = "0xFde71E607Fa694284F21F620ac2720291614FaCe";
export const L2_CORE_QUORUM_TRESHOLD = 5;
export const L2_TREASURY_QUORUM_TRESHOLD = 3;
export const L2_PROPOSAL_TRESHOLD = 100;
export const L2_VOTING_DELAY = 10;
export const L2_VOTING_PERIOD = 10;
export const L2_MIN_PERIOD_AFTER_QUORUM = 1;

//// L2 token
// 10 billion tokens (we use parseEther in script to add decimals)
export const L2_TOKEN_INITIAL_SUPPLY = "10000000000";
// 2 billion tokens (dummy value atm)
export const L2_NUM_OF_TOKENS_FOR_TREASURY = "2000000000";
// 8 billion tokens (dummy value atm)
export const L2_NUM_OF_TOKENS_FOR_TOKEN_DISTRIBUTOR = "8000000000";
// ARB token distributor (dummy value atm)
export const L2_TOKEN_DISTRIBUTOR_CONTRACT = "0xB991F7D5aa28762996BFc7AaA6DDF5D8591380cd"