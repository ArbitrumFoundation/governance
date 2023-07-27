# Security Council Management Contracts

todo: removal gov stuff

These contracts facilitate Security Council management and elections. 

For background information see sections 3 and 4 of the [Constitution of the Arbitrum DAO](https://docs.arbitrum.foundation/dao-constitution) as well as [this general overview of Arbitrum Governance](https://github.com/ArbitrumFoundation/governance/blob/main/docs/overview.md)

# High-level Election Overview

The Constitution specifies that membership of the Security Council is split into two cohorts. Every 6 months, all positions in a single cohort are put up for election.

The election implementation is split into:

- **Election stages:** The process for selecting and voting for nominees.
- **Update stages:** Installing the newly elected cohort into the Arbitrum smart contracts.

The election process and update stages are performed via on-chain smart contracts. A brief overview of each stage includes:

## Election Stages

Process for selecting and voting for the new cohort of Security council members.

1. **Nominee Selection (7 days).** Candidates must gain 0.2% of total votable tokens in order to make it to the next step.
2. **Compliance check by Foundation (14 days).** As dictated in the Constitution, the selected nominees must undergo a compliance check to ensure they comply with the legal requirements, service agreements, and additional rules dictated by the Constitution.
3. **Member election (21 days).** Votes are cast and the top 6 nominees are selected.

## Update Stages

Process to install the newly elected cohort of Security Council members into the Arbitrum smart contracts.

1. **Security Council manager update (0 days).** The manager is the source of truth for specifying who are the current council members. It processes the election result and takes note on who will be the new security council members.
2. **L2 timelock + withdrawal + L1 timelock (3 + 7 + 3 days).** All actions that directly affect the core Arbitrum contracts must go through a series of timelocks to protect the right for all users to exit. This is a built-in safety mechanism for users who are unhappy with the approved changes.
3. **Individual council update (0 days).** Once the updates have passed through the relevant timelocks, the Security Council manager can install the security council members. This requires updating 4 Gnosis Safe smart contracts that are controlled by the Security Council members.

![](./security-council-election-flow.png)

# Election Stages in detail

## 1. Nominee selection (7 days)

This stage consists of handling election timing, candidate registration, candidate endorsement:

- **Election creation.** Elections can be created by anyone, but only every 6 months. The election alternates between targeting the positions on the two cohorts. Once created, this first stage of the election process lasts for 7 days.
- **Candidate registration.** During these 7 days, any candidate can register, unless they are already a member of the other cohort. Members of the current cohort (the cohort up for election) are allowed to register for re-election.
- **Endorsing candidates.** Delegates can endorse a candidate during this 7 day window. A single delegate can split their vote across multiple candidates. No candidate can accrue more than 0.2% of all votable tokens.
- **Fallback in case of too few candidates.** In the event that fewer than 6 candidates receive a 0.2% endorsement, outgoing members of the cohort up for election will be selected to make up to 6 candidates.

### Implementation details

The nominee selection process is implemented by the `SecurityCouncilNomineeElectionGovernor` contract. 

It inherits most of its functionality from the OpenZeppelin Governor contracts and we have extended it with an extra feature: 

- Custom counting module to allow delegates to endorse multiple candidates.
- Overridden proposal and execution to make the governor single purpose.

This governor contract has the following general interface relevant to the first stage: 

- A new proposal is created each election cycle by calling `createElection`
- Contenders can make themselves eligible to receive votes by calling `addContender`.
- Delegates can call `castVoteWithReasonAndParams` or `castVoteWithReasonAndParamsBySig` supplying custom arguments in the params to indicate which candidate they wish to endorse with what weight.

## 2. Compliance check by the Foundation (14 days)

The Foundation will be given 14 days to vet the prospective nominees. If they find that a candidate does not meet the compliance check, they can exclude the candidate from progressing to the next stage. Note that grounds for exclusion could include greater than 3 members of a given organisation being represented in the nominee set (as described in section 4 of the Constitution).

### Implementation details

The foundation can exclude a nominee by calling `excludeNominee` function on the `SecurityCouncilNomineeElectionGovernor` contract.

If there are less than 6 eligible nominees, then the Foundation will consult with outgoing members of the cohort on whether they will continue in this role for another 12 months. Members of the existing cohort may be selected at random to fill the remaining seats. To fill an empty seat, the Foundation calls `includeNominee`

The Governor smart contract enforces the 2 week time period and the Foundation must exclude/include nominees by this deadline.

Once the compliance check has completed, anyone can call the `execute` function on the `SecurityCouncilNomineeElectionGovernor` to proceed to the member election stage.

## 3. Member election (21 days)

The voting process can begin once a set of compliant candidates have been successfully nominated. 

The voting process is designed to encourage voters to cast their vote early. Their voting power will eventually decay if they do not cast their vote within the first 7 days: 

- **0 - 7 days.** Votes cast will carry weight 1 per token
- **7 - 21 days.** Votes cast will have their weight linearly decreased based on amount of time that has passed since the 7 day point. By the 21st day, each token will carry a weight of 0.

Additionally, delegates can cast votes for more than one nominee: 

- **Split voting.** delegates can split their tokens across multiple nominees, with 1 token representing 1 vote.

### Implementation details

The Security Council member election will take place in a separate `SecurityCouncilMemberElectionGovernor` contract which will also inherit from OpenZeppelin Governor contracts. 

After the 14 day waiting period for the compliance check, anyone can trigger a new member election: 

- Call the execute function in `SecurityCouncilNomineeElectionGovernor` to create a new election proposal for `SecurityCouncilMemberElectionGovernor`

The `SecurityCouncilMemberElectionGovernor` includes:

- A custom counting module that allows delegates to split their vote and accounts for the linear decrease in voting weight.
- These additional parameters are supplied as the params argument when calling `castVoteWithReasonAndParams`.
- The custom counting module also checks that the account being voted for is a compliant nominee by checking against the list in the `SecurityCouncilNomineeElectionGovernor`.

At the end of the 21 days of election:

- Anyone can call `execute` on the `SecurityCouncilMemberElectionGovernor` contract to initiate the update of top 6 nominees with the most votes into `SecurityCouncilManager`.

# Update stages in detail

## 1. Security Council manager update

The `SecurityCouncilManager` is the entry point for updating council members. It contains the canonical list of security council members, and which cohort they are part of. When a member election completes, the manager updates its local list of the current cohorts then forms cross chain messages to propagate those updates to each of the Security Council Gnosis safes. 

The manager also provides some additional functionality to allow the security council to:

- **Remove a member.** As described in the Constitution, the council can remove one of its own members. The DAO can also remove a member under special condition described by the Constitution.
- **Add a member.** After removing a member, the council can add a member
- **Address rotation.** As a practical matter, a council member can rotate one of their own keys. This can only be done with the approval of at least 9/12 council members.

### Implementation details

The manager functionality is contained within a custom `SecurityCouncilManager` smart contract. Since the `SecurityCouncilManager` is indirectly able to make calls to the standard `UpgradeExecutor` contracts which have far reaching powers, special care must be take to ensure the manager only makes council member updates.

Calling the `UpgradeExecutor`s on each of the chains requires navigating withdrawals transactions, timelocks and inboxes, the `SecurityCouncilManager` outsources the calldata creation for these routes to the `UpgradeExecRouteBuilder` contract.

## 2. Timelocks and withdrawal

Constitutional DAO proposals all pass through:

- L2 timelock (3 days),
- L2 → L1 withdrawal (~7 days),
- L1 timelock (3 days).

You can read more about these stages in the [governance docs](https://github.com/ArbitrumFoundation/governance/blob/main/docs/overview.md#proposal-delays). The purpose of these delays is to ensure that users who wish to withdraw their assets before the proposal is executed will have the time to do so. Changing the Security Council members should also provide this guarantee, so after the election has completed and before the Security Councils are updated the update message also goes through these same stages. The update message will use the existing timelocks to enforce these delays.

### Implementation details

The existing governance timelock contracts are used as part of this flow. 

The `SecurityCouncilManager` is given the `PROPOSER` role on the L2 timelock enabling it to create messages that will eventually be received by each `UpgradeExecutor`

## 3. Individual council updates

The new Security Council members need to be installed into 4 Gnosis safes:

- Arbitrum One 9 of 12 Emergency Security Council
- Arbitrum One 7 of 12 Non-Emergency Security Council
- Ethereum 9 of 12 Emergency Security Council
- Nova 9 of 12 Emergency Security Council

The old cohort of members will be removed, and the new cohort will replace them.

### Implementation details

To do this the existing [Upgrade Executor contracts](https://github.com/ArbitrumFoundation/governance/blob/main/docs/overview.md#l1-upgrade-executor) on each chain will be installed as Gnosis Safe modules into the Security Council safes. A custom [Governance Action Contract](https://github.com/ArbitrumFoundation/governance/blob/main/src/gov-action-contracts/README.md) will be used to call the specific `OwnerManager` `addOwnerWithThreshold` and `removeOwner` methods on the Gnosis safes.

## Additional affordances

The Constitution also declares some other additional affordances to certain parties

1. The DAO can vote to remove a member prior to the end of their term, as long as 10% of possible votes are cast in favour and 5/6 of cast votes are in favour. This will be implemented as a governor with correct quorum and proposal passed thresholds. This governor will be given the rights to call `removeMember` on the `SecurityCouncilManager`.
2. The Security Council can remove a member prior to the end of their term, if 9 of 12 members agree. The 9 of 12 council will be given the rights to call `removeMember` on the `SecurityCouncilManager`.
3. The Security Council can add a member once one has been removed, if 9 of 12 members agree and if there are less than 12 members currently on the council. The 9 of 12 council will be given the rights to call `addMember` on the `SecurityCouncilManager`.
