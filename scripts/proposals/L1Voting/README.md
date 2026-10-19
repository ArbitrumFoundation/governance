# L1 Voting Proposal Payload

Grants `EXECUTOR_ROLE` to the L1 voting timelock on the L1 UpgradeExecutor and to its alias on the Arb One and Nova UpgradeExecutors.

How to verify:

1. Run the deploy script as a dry run with Foundry v1.8.3. Ensure the printed timelock matches `generate.bash`.
```bash
forge script scripts/l1-voting/DeployL1Voting.s.sol:DeployL1 --rpc-url $ETH_URL
```
1. Ensure the timelock alias is correct
1. Run `generate.bash` to regenerate `data.json`
