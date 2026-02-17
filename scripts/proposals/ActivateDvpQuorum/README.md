# Activate DVP Quorum Proposal Payload

NOTE THAT THE CURRENTLY DEPLOYED ACTION LIKELY HAS A STALE TOTAL DELEGATION ESTIMATE.

How to verify:

1. Read `DeployActivateDvpQuorumUpgrade.s.sol`
1. Run `DeployActivateDvpQuorumUpgrade.s.sol` with no rpc. Ensure the printed action address has code on arb1.
1. Read `generate.bash` and ensure that the printed action is included
1. Run `generate.bash` to regenerate `data.json`