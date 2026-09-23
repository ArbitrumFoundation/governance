# Glamsterdam action contracts

Parent chain pricing changes for Arbitrum One and Nova, gated on the Glamsterdam fork being live
on Ethereum.

## Contracts

| Contract | Chain | What it does |
| --- | --- | --- |
| `GlamsterdamForkGateAction` | Ethereum | Deploys its opcode probe in the constructor; `perform()` reverts unless SLOTNUM is available |
| `SetGlamsterdamGasParamsAction` | Arb One / Nova | Sets `parentGasFloorPerToken` to 16 and `perBatchGasCharge` to 530,000 |

The gate deploys a three-byte runtime, `SLOTNUM; POP; STOP` (`0x4b5000`), and stores its address
in the immutable `probe`. The repo's pinned solc 0.8.16 cannot emit SLOTNUM directly.
Calling the probe with 5,000 gas bounds the gas consumed by the undefined opcode before the fork;
after the fork the call succeeds.

## Deployment

1. Deploy `GlamsterdamForkGateAction` on Ethereum. Its constructor deploys the probe automatically.
   Read `probe()` and check its runtime is `0x4b5000`.
2. Deploy `SetGlamsterdamGasParamsAction` on both Arbitrum One and Nova. It takes no constructor
   arguments.
3. Build the proposal with the gate as a chain-1 action alongside the two L2 actions.

The L1 timelock executes the gate and creates the L2 retryables in one batch. A gate revert rolls
back the entire batch, which can be retried after the fork.

## Testing

Run the tests under both pre-fork and post-fork rules:

```
forge test --match-path 'test/gov-actions/glamsterdam/*' --evm-version osaka
forge test --match-path 'test/gov-actions/glamsterdam/*' --evm-version amsterdam
```

Foundry runs the selected EVM rules while passing a compatible target to solc 0.8.16.
`test_gateFollowsTheProbe` checks that the gate follows the real probe's result under either version.

## Showing a simulation before the fork

An unmodified pre-fork simulation reverts with `ForkNotActive()`. To simulate the post-fork path,
read the address from the deployed gate's `probe()` getter and override that account's bytecode
with a bare `STOP` (`0x00`):

```json
{ "stateOverrides": { "<probe address>": { "code": "0x00" } } }
```

Both `STOP` and the post-fork probe succeed and return no data. The gate itself runs unmodified.
Publish the unmodified and overridden simulations, identifying the override used.

## Caveats to re-check before this goes to a vote

- Re-check EIP-7773 to confirm SLOTNUM is included in Glamsterdam. If it is dropped, update the
  probe bytecode before deploying the gate.
- Validate the 530,000 per-batch charge against the final EIP-8037 text and devnet measurements
  for both chains.
- `parentGasFloorPerToken` is set to 16 for potential future use on chains using blob or Alt DA.
- The L2 tests use mocked precompiles. They check calls and post-state assertions, but real ArbOS
  execution and batch pricing still need devnet validation.
