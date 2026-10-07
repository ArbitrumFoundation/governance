## L1 Voting System Components

- **`L1ArbitrumGovernor`:** A modified OpenZeppelin governor that creates proposals, checks proven voting power, records votes, and queues successful proposals.
- **`L1ArbitrumTimelock`:** A new deployment of the existing L1 Timelock implementation.
- **`DelegateMapping`:** A contract deployed on L1 and L2 that links an L1 voting address to an L2 delegate.
- **`L2StateMirror`:** A contract that checkpoints confirmed assertions and stores L2 state values proven against them.
- **`ProofHelper`:** A helper contract for handling L2 block headers and storage proofs.
- **`VotingTokenMirror`:** The governor-facing interface that resolves L1 voters to L2 delegates and returns proven voting power and quorum inputs.

## L1 Voting User Flow

The general flow for using the L1 voting system is as follows:

Delegates whose address is a contract must register their L1 voting address in the `DelegateMapping` on L2 before voting on any L1 proposal. Registration should ideally be performed before any L1 proposal is created, but delegates will have up to 3 days to register after any L1 proposal is created.

Delegates whose address is an EOA are not required to register their L1 counterpart address on L2. Instead, they can present a signature to the `L2StateMirror` contract on L1 before they cast their vote or make a proposal.

To create a new proposal on L1, a delegate must:

1. Call `L2StateMirror.checkpointAssertion` to store the latest confirmed assertion as of the current L1 block
1. Call `L2StateMirror.proveL2BlockHeader` to prove and store the L2 state root and L2 block number committed to by the previously checkpointed assertion
1. Call `L2StateMirror.proveTokenStorageRoot` to prove and store the ARB token contract's storage root
1. Call `L2StateMirror.proveVotes` to prove and store their voting power
1. Depending on whether the delegate is an EOA or contract on L2:
    1. If contract: 
        1. Call `L2StateMirror.proveDelegateMappingStorageRoot` to prove and store the L2 `DelegateMapping` contract's storage root
        1. Call `L2StateMirror.proveL1Address` to prove and store the delegate's claimed L1 address
    1. If EOA:
        1. Call `L2StateMirror.claimL1AddressBySig` to claim and store the delegate's L1 address
1. From the L1 address, call `DelegateMapping.claim` on L1 to claim the L2 delegate
1. Call `L1ArbitrumGovernor.propose` within the lookback period of 300 L1 blocks

To vote in an L1 proposal, the first voter must:

- Perform steps 1-6 from above
- Call `L2StateMirror.proveTotalDelegation` to prove and store the ARB token contract's total delegation
- Call `L2StateMirror.proveVotes(EXCLUDE_ADDRESS)` so quorum can be properly calculated
- Call `L1ArbitrumGovernor.lockProposalSnapshot`

Subsequent voters only need to perform steps 4-6 before voting, proving against the assertion checkpointed at the locked snapshot block. Step 6 is one time per L1 address, not per proposal.

The proving steps and `lockProposalSnapshot` are permissionless so they can be performed by any account.

## Censorship

We assume an attacker has a 7 day "censorship budget" as defined in the [BoLD whitepaper](https://arxiv.org/abs/2404.10491).

There are essentially four actions which can be censored. An attacker can distribute their censorship power across multiple actions.
- Moves in the rollup protocol
    - An attacker can delay assertion confirmation by 7 additional days, making worst case assertion confirmation time 14 days.
    - An attacker can use this to make the latest confirmed state used for proposing/voting up to 14 days old, instead of the 7 days expected.
- Checkpointing assertions in the `L2StateMirror`
    - An attacker can delay checkpointing by 7 days. 
    - Since a fresh checkpoint is required to create a proposal, this could delay proposal creation.
    - Since a checkpoint must be made within the voting period before the first vote is cast, it could delay the first vote by up to 7 days after the voting period starts.
- Creating proposals
    - An attacker can censor proposal creation transactions and/or checkpointing until the desired threshold block is older than the max lookback. An attacker can repeat this to delay proposal creation for 7 days.
- Voting on proposals
    - An attacker can censor checkpointing and/or the first vote for 7 days. 
    - An attacker can do this to shorten the effective voting period by 7 days.
    - An attacker can do this to pick when to checkpoint the voting power for an existing proposal.

## Key Durations

We assume that the sequencer either does not censor, or its censorship capability is already factored into the existing governance durations these new durations are based on.

**Voting Delay - 17 days:** On L2, voting delay is 3 days to give delegates time to muster voting power in response to a new proposal. To preserve 3 days of reaction time, we add 14 days for worst case assertion confirmation time.

**Voting Period - 21 days:** On L2, the voting period is 14 days. An attacker can censor checkpointing and the first vote to shorten the effective voting period by up to 7 days (see Censorship). To preserve 14 days of effective voting time, we add 7 days.

**Max Proposal Block Lookback - 1 hour:** Max age of the threshold block named in `propose()`, at which the proposer's voting power is checked. One hour is ample time to checkpoint an assertion, prove the proposer's votes against it, and land the propose transaction, without letting proposers reach far back for stale voting power.

**Timelock Min Delay - 25 days:** Worst case assertion confirmation time of 14 days plus the L2 timelock delay of 8 days plus the L1 timelock delay of 3 days. A user who reacts to a passed malicious proposal within 8 days can initiate an exit and have it confirmed before the proposal executes. See [proposal delays](overview.md#proposal-delays).

## L1 Address Claims

A delegate's L2 voting power is only usable on L1 by the L1 address registered for the delegate against the assertion being voted on. There are two ways to register it:

- **`DelegateMapping.claim` on L2, proven with `L2StateMirror.proveL1Address`.** Works for any account, contracts included. Claiming the zero address revokes: the zeroed slot is unprovable on L1.
- **`L2StateMirror.claimL1AddressBySig`.** An EIP-712 signature from an EOA delegate, submittable by anyone. Skips the L2 claim and proof entirely.

The signed struct carries no nonce or deadline.

## Rollup Failure Modes

The system's only rollup dependency is `L2StateMirror.checkpointAssertion`, which queries `Rollup.latestConfirmed()` and `Rollup.getAssertion()` through a gas-bounded staticcall. The live result is used only if `latestConfirmed` returns exactly 32 nonzero bytes and `getAssertion(latest)` returns an exactly sized node with status `Confirmed`. Otherwise the mirror falls back to its cached last seen assertion.

### Caught

These fall back to the cached assertion. Checkpointing never bricks and uses the live value again as soon as the rollup returns a valid response:

- Reverts, including revert bombs
- Empty returndata
- Wrong-size returndata: short, oversized, or return bombs (the returndata copy is capped)
- Burning all forwarded gas (forwarded gas is capped)
- `latestConfirmed()` returning zero
- `getAssertion` status anything other than `Confirmed`

A caller cannot fake unreachability by starving `checkpointAssertion` of gas: it reverts with `GasTooLowForRollupCall` rather than query the rollup with less than a floor of gas.

A stalled assertion chain (rollup paused, validators offline, etc.) is also tolerated: checkpoints keep committing the last confirmed assertion, so voting continues on correspondingly stale L2 state.

### Uncaught

The mirror trusts any well-formed response:

- **The rollup confirms an assertion with an incorrect L2 state root**: incorrect voting power becomes provable.
- **`latestConfirmed` returns a wrong but well-formed value that passes the `getAssertion` status check**:
  - If the value is a real confirmed assertion hash (e.g. an old one), its possibly stale state is provable.
  - If it is not a real assertion hash, no preimage can satisfy `proveL2BlockHeader`, so nothing can be proven against it and no proposals can be made until the rollup returns a valid response again.

## Breaking Changes & Upgrades

Below is a list of changes outside the L1 voting system that would break it. Under each breaking change is an upgrade to the L1 voting system that should accompany the breaking change itself.

This is not an exhaustive list of potentially breaking changes.

**Rollup migrates to a new address:** Proxy upgrade the `L2StateMirror` to point to the new rollup

**`Rollup.latestConfirmed` is renamed or its behavior changes:** Proxy upgrade `L2StateMirror` to fetch the assertion hash in a different way

**`Rollup.latestConfirmed` or `Rollup.getAssertion` becomes more gas-intensive:** Proxy upgrade `L2StateMirror` to bump the gas forwarded.

**Assertion format changes:** Proxy upgrade `L2StateMirror` to understand the new format

**L2 block header format changes:** Proxy upgrade `ProofHelper` to decode the new header. The state root and block number are read by field index (3 and 8), so fields appended after them are safe, but the vendored `RLPReader` caps a header at 32 fields.

**L2 or L1 Timelock duration changes:** Set the min delay of the L1 Timelock to 14 plus the new L1+L2 delay

**Worst case assertion confirmation time changes:**
1. Set the min delay of the L1 Timelock to the L1+L2 timelock delays plus the new worst case assertion confirmation time
1. Set the voting delay of the L1 governor to the L2 core governor voting delay plus the new confirmation time

**L2 core governor parameters change:** Mirror the changes appropriately in the L1 governor

**L2 state trie changes:** 
1. Proxy upgrade `ProofHelper` to understand the new trie
1. If the interface of `ProofHelper` changes, proxy upgrade the `L2StateMirror`
1. Upgrade the `L1ArbitrumGovernor` to revert on execution of any proposal with snapshot block earlier than the upgrade. This prevents a proposal from using a partial voter set due to unproven voting power being unprovable after the upgrade.

**Quorum calculation on L2 changes, this includes dependencies of the quorum calculation such as where the total DVP is stored in the token:**
1. Upgrade the `L1ArbitrumGovernor` to revert on execution of any proposal with snapshot block earlier than the upgrade.
1. Upgrade or redeploy the `L2StateMirror` to mirror the correct information.
1. Possibly reset the token in the governor to the new state mirror