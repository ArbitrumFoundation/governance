# Gotchas

_The following is a list of quirks and/or potentially unexpected behaviors in the Arbitrum Governance implementation. General familiarity with the architecture is assumed (start [here](./overview.md))_.  


- **Abstain Vote** 
Voting “abstain” on a core-governor or governor proposal does not count as either a “for” or “against” vote, but does count towards reaching quorum (5% or 3% of votable tokens, respectively).
- **Timelock vs Governor Execution** 
An operated queued in the core-governor-timelock or the treasury-governor-timelock can be executed permissionlessly on either its associated governor (typical) or on the timelock itself (atypical). The execution will be the same in either case, but in the later case, the governor’s `ProposalExecuted` event will not be emitted.
- **L1-to-L2 Message Fees in scheduleBatch**
 When executing a batch of operations on the L1ArbitrumTimelock, if more than one operation creates a retryable ticket, the full `msg.value` value will be forwarded to each one. For the execution to be successful, the `msg.value` should be set to `m `and the L1ArbitrumTimelock should be prefunded with at least `m * n` ETH, where `m` is the max out of the costs of each retryable ticket, and `n` is the number of retryable tickets created.
- **Two L1 Proxy Admins** 
The Outbox has a different proxy admin than all of the other governed L1 contracts; this is simply a vestige of how the core contracts were initially deployed. Note that both proxy admins have the same owner (the DAO), and thus this has no material effect on the DAO's affordances.
- **Non-excluded L2 Timelock**
  In the both treasury timelock and the DAO treasury can be transfered via treasury gov DAO vote; however, only ARB in the DAO treasury is excluded from the quorum numerator calculation. Thus, the DAO’s ARB should ideally all be stored in the DAO Treasury. (Currently, the sweepReceiver in the TokenDistributor is set to the timelock, not the DAO treasury.)
- **L2ArbitrumGovernoer onlyGovernance behavior**
Typically, for a timelocked OZ governror, the `onlyGovernance` modifier ensures a call is made from the timelock; in L2ArbitrumGoverner, the _executor() method is overriden such that `onlyGovernance` enforces a call from the governor contract itself. This ensures calls guarded by `onlyGovernance` go through the full core proposal path, as calls from the governor could only be sent via `relay`. See the code comment on `relay` in [L2ArbitrumGoveror](../src/L2ArbitrumGovernor.sol) for more.

- The `UpgradeExecRouteBuilder` contract is immutable; instead of upgrading it, it can be redeployed, in which case any references to its address should be updated as well (currently only referenced in SecurityCouncilManager).
- The `UpgradeExecRouteBuilder`'s l1TimelockMinDelay variable should be equal to the minimum timelock delay on the core L1 timelock. If, for whatever reason, the value on the L1 timelock is ever increased, the UpgradeExecRouteBuilder should be redeployed with the new value accordingly.
- Changes to members of the security council should be initiated via the SecurityCouncilManager, not via calling addOwner/removeOwner on the multisigs directly. This ensures that the security council's two cohorts remain properly tracked. 
- Voting abstain on a SecurityCouncilMemberRemovalGovernor proposal is disallowed. 
