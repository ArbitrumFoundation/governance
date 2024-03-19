# Governance Action Contracts
A Governance Action Contract (GAC) is a contract used by governance to execute a specific on-chain action. GACs are meant to be called only by the [UpgradeExecutor](../UpgradeExecutor.sol) contracts' `execute` method, which uses the Upgrade Contract via `delegatecall`. 

(See  [proposal lifecycle example](../../docs/proposal_lifecycle_example.md) for a detailed overview of the steps involved in governance execution.) 

This subdirectory includes a number of Governance Action Contracts Arbitrum Governance may at some point opt to use. Note that many of these contracts — e.g., `PauseInboxAction` — would only ever be used in a time-sensitive emergency; they are included only so that the community is prepared to act swiftly if and when such an emergency arises. 


## Governance Action Contract Standards and Guidelines

The following standards/guidelines for GACs are meant to maximize the work (engineering, auditing, etc.) that can be performed prior to the point at which an upgrade is planned, and minimize the potential for human error when/if an upgrade is planned for execution. They also tend towards simplicity and consistency:


1. GACs **must** be safe targets for delegatecall; in particular, they must use no state variables, and only use variables stored in bytecode (`immutable` or `constant` variables.) 
1. A GAC should have only one external function; it should be named `perform` and it should take no parameters. 
1. If the GAC needs to use a core protocol contract address, it should retrieve it from one of the [Address Registry contracts](../../src/gov-action-contracts/address-registries/L1AddressRegistry.sol) and set its value in the GAC's constructor (as opposed to passing int the core protocol contract address directly). The deployed addresses of the address registry contracts can be found in the mainnet [deployedContracts.json](../../files/mainnet/deployedContracts.json) file.
1. A GAC should typically be composed of a general version with values set in the constructor, and then a contract specific to the proposal that inherits the general version, sets all parameters in the parent constructor, and includes no constructor parameters itself (see below).
1. GACs should preform checks on the expected state before and after the action's execution if possible, and should explicity revert on failure.
1. GACs contract names should be suffixed with `Action`.

## Using libraries
The GAC author should also consider writing the GAC `perform` function logic in a Solidity library, then calling the library from the GAC. When doing this, library authors should make the library functions internal, as an external function will trigger another delegate call. 
The advantages of using a library are:
* Libaries can called by other GACs, enabling GAC logic to be re-used.
* Solidity libraries restrict access to storage to the function argument list (except when using assembly), this helps to ensure the GAC is not acessing storage (see 3. above)

The disadvantage of this approach is that calling multiple libraries from a GAC may lead to a confusing and complicated call path. 

Judging this tradeoff is up to the author, but the focus should always be on readiblity and auditability of the code.

## Example
In following example, we show an action contract for setting the address 0xa4b174a3D79899E41aA7180f7934fa7a9f63C52F (arbitrarily chose for this example) as a batch-poster on Arbitrum Nova; this involves a simple call to the `sequencerInbox.setIsBatchPoster` method. We include annotation emphasizing the guidelines above:



```solidity
// General version of contract, with values set in constructor params, for testing and potential re-use in future proposals.
// Detailed contract name, suffixed with "Action"
contract SetIsBatchPosterAction {
    // No state variables; values are all immutable for safe delegatecalling.
    // Values are also public for ease of external verification.
    ISequencerInbox public immutable sequencerInbox;
    address public immutable batchPoster;
    bool public immutable newBatchPosterstatus;

    constructor(
        ISequencerInboxGetter _l1AddressRegistry,
        address _batchPoster,
        bool _newBatchPosterstatus
    ) {
        // Sequencer inbox is not passed in as param; instead, address registry is, and sequencerInbox is retrieved and then set to immutable variable.
        sequencerInbox = _l1AddressRegistry.sequencerInbox();
        batchPoster = _batchPoster;
        newBatchPosterstatus = _newBatchPosterstatus;
    }

    // Only external method is perform with no parameters
    function perform() external {
        // Preform the expected prior state sanity check; revert on failure.
        require(
            sequencerInbox.isBatchPoster(batchPoster) != newBatchPosterstatus,
            "SetIsBatchPosterAction prior batch poster status"
        );

        // Perform the external call; note that it's the UpgradeExecutor, with the ownership affordance to call setIsBatchPoster,
        // that will be making this call (by delegating to this action contract.)
        sequencerInbox.setIsBatchPoster(batchPoster, newBatchPosterstatus);

        // Perform the expected post state sanity check; revert on failure.
        require(
            sequencerInbox.isBatchPoster(batchPoster) == newBatchPosterstatus,
            "SetIsBatchPosterAction post batch poster status"
        );
    }
}
// Child contract with values specific to this proposal
// Detailed name, suffixed with "Action"
contract SetNovaBatchPosterAction is SetIsBatchPosterAction {
    // constructor takes no parameters
    constructor()
        // all values are set in parent constructor
        SetIsBatchPosterAction(
            0x2F06643fc2CC18585Ae790b546388F0DE4Ec6635, // L1 address registry for Nova
            0xa4B174a3d79899e41Aa7180F7934fA7a9F63C52F, // batch poster
            true // status to set
        )
    {}
}

```
