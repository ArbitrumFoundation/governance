# Security Council Manager as a source of truth

The Security Council Manager is the source of truth for the membership of all Security Councils on all chains where they are deployed. It contains a registered list of Security Councils, which it will update with any changes to membership.

All changes to membership should be made through the manager, which will then propagate these changes to the councils. Any changes made directly to the councils will be overwritten the next time the Manager pushes an update. As a reminder the normal flow for an election is:
- **SecurityCouncilNomineeElectionGovernor.createElection** - called at T+0 where T is a multiple of 6 months after the first election date
- **SecurityCouncilNomineeElectionGovernor.execute** - called at T+21 days
- **SecurityCouncilMemberElectionGovernor.execute** - called at T + 42 days
- **ArbitrumTimelock.execute** (on L2) - called at T + 42 days
- **Outbox.executeTransaction** - called at T + 49 days
- **L1ArbitrumTimelock.executeBatch** - called at T + 52 days
- Retryable ticket execution on ArbOne and Nova - also called at T + 52 days


## Public functions

### Replace cohort

Can only be called by the Member Election Governor. It is used to replace a whole cohort of (6) members. This is the function that will be called for the standard elections that take place every 6 months.

### Remove member

Can be called by the Emergency Security Council and the Removal Governor. Is used to remove a member. The Constitution allows members to be removed if 9 of 12 members wish them to be, or if the DAO votes to remove a member and 10% of votable tokens cast a vote, with 5/6 of voted tokens are in favour of removal.

### Add member

Can only be called by the Emergency Security Council. Can only be called if the there are less than 12 members in the Security Council because at least one has been removed.

### Replace member

Can only be called by the Emergency Security Council. This is a utility function to allow the council to call Remove and Add in the same transaction. Semantically this means that an entity has been removed from the council, and a different one has been added.

### Rotate member

Can only be called by the Emergency Security Council. Functionally this is the same as Replace, however semantically it infers different intent. Rotate should be called when a entity wish to replace their address, but it is the same entity that controls the newly added address.

### Add Security Council

Can be called by DAO and the emergency security council. Adds an additional security council whose members will be updated by the election system. 

### Remove Security Council

Can be called by DAO and the emergency security council. Removes a security council from being updated by the election system.


## Race conditions
Since the Security Council Manager can be updated from a number of sources race conditions can occur in the updates. Some of these updates are long lived processes (the elections), so care must be taking to avoid these kinds of race conditions.

Below we'll explain the possible sources of races, and how they're mitigated.

### Standard elections
Standard elections take place every 6 months, and last 42 days before replacing the cohort in the Manager. The election governors do checks to ensure that a contender will not become a member of both cohorts, and this is then later enforced in Manager. However, whilst the elections are ongoing the membership in the Manager may be manipulated causing the result of the election to conflict (eg by adding a potential nominee to the previous cohort in the manager). This would cause the election execution to revert.

The election contracts deal with this situation by essentially pausing the election pipeline until it is "unblocked". The election result will wait as an unexecuted proposal in the Member Election Governor; the Nominee Selection Governor will not allow the next election to be created until the previous proposal has executed, therefore meaning that no election results can be propagated to the Manager until the conflict is resolved.

Since the conflict can only have been created by adding an individual member - something only the Security Council can do - it is then expected that the Security Council should unblock the pipeline by removing the member they added and allowing the election to complete. Therefore should the Security Council call the `rotateMember`, `replaceMember` or `addMember` methods they should ensure that they do not do so for accounts that are contenders or nominees in an ongoing election. In particular:

> If an address is being added to the previous cohort whilst an election is ongoing it must not be the same as any of the contenders or nominees in that election

### Removal elections
Elections occuring in the Removal Governor will result in a member being removed. However it could be that by the time the proposal to remove the member completes the member has already been removed by some other means. In this case the removal proposal will block, being unable to execute.

To address this an expiry has been added to Succeeded removal proposals, such that if a successful removal proposal has not been executed within the expiry period it will transition into an Expired state and will not be able to be executed at a later date. The execute function can be called by anyone, so someone should ensure that this is called on a successful proposal before it expires.

### Propagation races
After an update occurs in the Manager it is propagated to all registered Security Councils. This propagation goes through a number of steps, including timelocks, withdrawals and potentially retryable transactions. Each of these stages can be executed by anyone, however if one these stages wasn't executed then the update might remain waiting at one of the stages. It's possible that at this point another update could overtake a previous one, the final execution of the updates might then occur out of order.

To mitigate this the Member Sync Action contract which is the last step in updating the membership on the Security Council Gnosis Safe uses a key value store to store an ordered update nonce that ensure no later update can be made before an earlier one.