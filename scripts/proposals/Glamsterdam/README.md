# Glamsterdam Proposal Payload

Sets the parent chain gas params on Arbitrum One and Nova, gated on the Glamsterdam fork being
live on Ethereum. See the [action contracts README](../../../src/gov-action-contracts/glamsterdam/README.md).

How to deploy:

1. Run `DeployGlamsterdamActions.s.sol` once per chain. It deploys the gate on Ethereum and the gas
   params action on Arbitrum One and Nova.

   ```
   forge script scripts/proposals/Glamsterdam/DeployGlamsterdamActions.s.sol --evm-version osaka \
     --rpc-url <ethereum rpc> --account <keystore> --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
   forge script scripts/proposals/Glamsterdam/DeployGlamsterdamActions.s.sol \
     --rpc-url https://arb1.arbitrum.io/rpc --account <keystore> --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
   forge script scripts/proposals/Glamsterdam/DeployGlamsterdamActions.s.sol \
     --rpc-url https://nova.arbitrum.io/rpc --account <keystore> --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
   ```

   `--evm-version osaka` matches Ethereum before the fork. Without it, gas is estimated under the
   repo's default Amsterdam rules, several times above the real cost. It does not change the bytecode.
1. Run `generate.bash` to write `data.json`.

How to verify:

1. Read `DeployGlamsterdamActions.s.sol`
1. Run `DeployGlamsterdamActions.s.sol` with no rpc, once with `--chain-id 1` and once with
   `--chain-id 42161`. Ensure the gate address has code on Ethereum, the probe's code is `0x4b00`,
   and the gas params action address has code on both Arbitrum One and Nova.
1. Read `generate.bash` and ensure that the printed addresses are included
1. Run `generate.bash` to regenerate `data.json`
