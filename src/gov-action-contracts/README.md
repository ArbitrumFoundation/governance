# Governance Action Contracts
A Governance Action Contract (GAC) is a contract used by governance to execute a specific on-chain action. GACs are meant to be called only by the [UpgradeExecutor](../UpgradeExecutor.sol) contracts' `execute` method, which uses the Upgrade Contract via `delegatecall`. 

(See  [proposal lifecycle example](../../docs/proposal_lifecycle_example.md) for a detailed overview of the steps involved in governance execution.) 

This subdirectory includes a number of Governance Action Contracts Arbitrum Governance may at some point opt to use. Note that many of these contracts — e.g., `PauseInboxAction` — would only ever be used in a time-sensitive emergency; they are included only so that the community is prepared to act swiftly if and when such an emergency arises. 


### Governance Action Contract Standards and Guidelines

The following standards/guidelines for GACs are meant to maximize the work (engineering, auditing, etc.) that can be performed prior to the point at which an upgrade is planned, and minimize the potential for human error when/if an upgrade is planned for execution. They also tend towards simplicity and consistency:

1. A GAC should have only one external function, and it should be named `perform`. 
2. `perform` should accept as few parameters as possible, only accepting parameters where absolutely necessary. 
    Examples:
    - Instead of `perform` accepting a boolean parameter, create two distinct Upgrade Contracts, one which implements the `true` condition and one which implements the `false` condition.
    - Instead of `perform` accepting the contract address of a core protocol contract on (say) either Arbitrum One or Arbitrum Nova, deploy two GACs, which get access to the appropriate contract address via constructor params.
3. GACs should not access or modify their own state (since they are called via `delegatecall`). Any state variables on the contract should thus be `immutable` or `constant` (as these are not stored in state).
4. GACs contract names should be suffixed with `Action`.
5. GACs should revert on failure.
