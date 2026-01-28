# Activate DVP Quorum Proposal Payload

NOTE THAT THE ACTION HAS NOT BEEN DEPLOYED, THIS IS BECAUSE WE WILL RESET TOTAL DELEGATION ESTIMATE SHORTLY BEFORE PROPOSAL SUBMISSION.
THIS REQUIRES A REDEPLOYMENT OF THE ACTION.

How to verify:

1. Read `DeployActivateDvpQuorumUpgrade.s.sol`
1. Run `DeployActivateDvpQuorumUpgrade.s.sol` with no rpc. Ensure the printed action address has code on arb1.
1. Ensure that the printed action is contained in `generate.bash`
1. Run `generate.bash` to regenerate `data.json`