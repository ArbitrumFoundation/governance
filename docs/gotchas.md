# Gotchas

_The following is a list of quirks and/or potentially unexpected behaviors in the Arbitrum Governance implementation. General familiarity with the architecture is assumed (start [here](./overview.md))_.  


- **Abstain Vote** 
Voting “abstain” on a core-governor or treasury governor proposal does not count as either a “for” or “against” vote, but does count towards reaching quorum (5% or 3% of votable tokens, respectively). Voting abstain on a security council member removal proposal is disallowed.

- **Late Quorum Extension**
The core, treasury, and security-council-member-removal governors all have a minimum 14-day voting period, and use open zeppelin's "late quorum" module to add a late-quorum extension of 2 days. This ensures that there are always at least 2 days of voting after a proposal's quorum is reached; i.e., the maximum total voting period would be 16 days, when/if quorum is reached at the very end of the initial 14-day period. 

- **Timelock vs Governor Execution** 
An operation queued in the core-governor-timelock or the treasury-governor-timelock can be executed permissionlessly on either its associated governor (typical) or on the timelock itself (atypical). The execution will be the same in either case, but in the later case, the governor’s `ProposalExecuted` event will not be emitted.

- **Multiple L1 Proxy Admins** 
There are 3 L1 proxy admins - one for the governance contracts, one for the governed core Nitro contracts of Arb1, and one for the governed core Nitro contracts of Nova. Note that all proxy admins have the same owner (the DAO), and thus this has no material effect on the DAO's affordances.

- **Non-excluded L2 Timelock**
ARB in both the treasury timelock and the DAO treasury can be transferred via treasury gov DAO vote; however, only ARB in the DAO treasury is excluded from the quorum numerator calculation. Thus, the DAO’s ARB should ideally all be stored in the DAO Treasury. 

- **L2ArbitrumGovernoer onlyGovernance behavior**
Typically, for a timelocked OZ governror, the `onlyGovernance` modifier ensures a call is made from the timelock; in L2ArbitrumGoverner, the _executor() method is overriden such that `onlyGovernance` enforces a call from the governor contract itself. This ensures calls guarded by `onlyGovernance` go through the full core proposal path, as calls from the governor could only be sent via `relay`. See the code comment on `relay` in [L2ArbitrumGoveror](../src/L2ArbitrumGovernor.sol) for more.

- **UpgradeExecRouteBuilder Quirks**
- The `UpgradeExecRouteBuilder` contract is immutable; instead of upgrading it, it can be redeployed, in which case any references to its address should be updated as well (currently only referenced in SecurityCouncilManager). Additionally, UpgradeExecRouteBuilder`'s l1TimelockMinDelay variable should be equal to the minimum timelock delay on the core L1 timelock. If, for whatever reason, the value on the L1 timelock is ever increased, the UpgradeExecRouteBuilder should be redeployed with the new value accordingly.

- **Security Council Member Updates**
- Changes to members of the Security Council should be initiated via the SecurityCouncilManager, not via calling addOwner/removeOwner on the multisigs directly. This ensures that the security council's two cohorts remain properly tracked in the SecurityCouncilManager contract.  

- **UpgradeExecutor Affordance** 

Affordances are always given to the DAO via an UpgradeExecutor contract, which grants affordance to both the core governor proposal path and the Security Council. This includes abilities that are intended only for the Security Council; for example, proposal cancellation, practically speaking, could/would only ever be preformed by the Security Council (since the DAO wouldn't have time to vote on and execute a cancellation). Still, for this case, the affordance is given to the UpgradeExecutor; this is done for clarity, consistency, and to ensure that the UpgradeExecutor is the single source of truth for execution rights.

The only affordances granted directly to the Security Council (and not to its corresponding UpradeExecutor) are the "MEMBER_ADDER", "MEMBER_REPLACER", "MEMBER_ROTATOR", and "MEMBER_REMOVER" roles on the SecurityCouncilManager contract. If the emergency Security Council on Arbitrum One is ever either removed or deployed to a new address, these roles should be modified accordingly.
