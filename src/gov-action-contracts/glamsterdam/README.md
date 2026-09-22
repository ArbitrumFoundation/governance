# Glamsterdam action contracts

Parent chain pricing changes for Arbitrum One and Nova, to take effect once the Glamsterdam fork is
live on Ethereum, gated so that they cannot execute before it is.

## Contracts

| Contract | Chain | What it does |
| --- | --- | --- |
| `SlotNumProbe` (library) | Ethereum | Deploys the 3-byte probe `SLOTNUM; POP; STOP` |
| `OpcodeForkGateAction` | Ethereum | Reverts unless the probe call succeeds |
| `GlamsterdamForkGateAction` | Ethereum | The above, wired to the deployed probe |
| `SetGlamsterdamGasParamsAction` | Arb One / Nova | Sets `parentGasFloorPerToken` and `perBatchGasCharge` |
| `ArbOneSetGlamsterdamGasParamsAction` | Arb One | 16 and 530,000 |
| `NovaSetGlamsterdamGasParamsAction` | Nova | 16 and 530,000 |

## How the gating works

The L1 timelock executes every action in a proposal in one `executeBatch` call, and that includes
creating the retryable tickets that carry actions to Arbitrum One and Nova. A revert in any element
reverts the batch, ticket creation included. So a single host chain gate action gates the L2 actions
too — they are in the same atomic call.

OpenZeppelin's `TimelockController` marks an operation done only once every call in the batch has
succeeded, and operations never expire. A batch that reverts on the gate therefore stays `Ready`,
and anybody can execute it again after the fork. This is the same mechanism `OfficeHoursAction`
relies on.

The gate detects the fork rather than trusting a timestamp, because Glamsterdam has no announced
mainnet activation time and the date has slipped repeatedly. `notBeforeTimestamp` exists as a
backstop against a misconfigured probe and is set to 0.

## Deployment order

1. Deploy the probe on Ethereum. Use the canonical CREATE2 factory so the address is known before
   the proposal is drafted:

   ```
   cast send 0x4e59b44847b379578588920cA78FbF26c0B4956C \
     <32-byte-salt>624b50006000526003601df3 --rpc-url $ETH_RPC
   ```

   Then check the runtime is exactly `0x4b5000`:

   ```
   cast code <probe> --rpc-url $ETH_RPC
   ```

2. Fill the probe address into `GlamsterdamForkGateAction` and deploy it on Ethereum. The
   constructor reverts on a codeless probe, so this cannot be deployed against a wrong address.
3. Deploy `ArbOneSetGlamsterdamGasParamsAction` on Arbitrum One and
   `NovaSetGlamsterdamGasParamsAction` on Nova.
4. Build the proposal with the gate as a chain-1 action alongside the two L2 actions.

## Testing

The fork gate has to be exercised on both sides of the fork. foundry clamps the version it hands
solc independently of the version it runs the EVM at, so `--evm-version amsterdam` does not break
the repo's pinned solc 0.8.16 — solc still receives `london` while revm executes Amsterdam rules.
Nothing needs to change in `foundry.toml`, and nothing should: the rest of the suite belongs on
current rules.

```
forge test --match-path 'test/gov-actions/glamsterdam/*' --evm-version osaka
forge test --match-path 'test/gov-actions/glamsterdam/*' --evm-version amsterdam
```

`test_gateFollowsTheProbe` asserts the gate passes exactly when SLOTNUM is available, so it asserts
the right thing at either version.

## Showing a simulation before the fork

Tenderly has no EVM hardfork selector — "fork" in their docs means copying chain state, not
selecting protocol rules — so every pre-fork simulation of the gate will revert with
`ForkNotActive()`. That is correct behaviour, and worth showing, but it is not a useful trace of
what the proposal does.

Tenderly does support overriding an account's bytecode, through State Overrides in the simulator UI,
`tenderly_setCode` on a Virtual TestNet, or `code` in `stateOverrides` on `eth_simulateV1`. Override
**the probe**, not the gate, with a bare `0x00`:

```json
{ "stateOverrides": { "<probe address>": { "code": "0x00" } } }
```

After the fork the probe runs `SLOTNUM; POP; STOP`: succeeds, returns nothing. A bare `STOP`
succeeds and returns nothing. Indistinguishable to the caller, so the gate takes the post-fork
branch and the rest of the proposal traces normally — with the gate's own bytecode, the thing under
review, running unmodified. `test_gatePassesWhenProbeSucceeds` pins this equivalence.

Publish both simulations: the unmodified one, which proves the gate is real rather than decorative,
and the overridden one, which shows what executes. Say plainly which override was applied and why.

## Caveats to re-check before this goes to a vote

- **EIP-7843 is scheduled for inclusion, not frozen.** Re-check EIP-7773 before deploying. If
  SLOTNUM is dropped, deploy a probe for a different fork-introduced opcode and point the gate at
  it; the gate itself needs no change.
- **`perBatchGasCharge` is set to 530,000.** Validate batch posting costs on a devnet; see the TODO in
  `ArbOneSetGlamsterdamGasParamsAction`.
- **`parentGasFloorPerToken` will not bind while the chains post blob batches only.** It is set
  anyway so the chains mirror the parent chain rule. The economically live change is
  `perBatchGasCharge`.
- **The L2 tests run against etched mocks, not ArbOS.** They check the action calls the right
  precompile methods with the right arguments; they cannot tell you ArbOS accepts 16, or that 530,000
  prices batches correctly. That needs a nitro devnet.
