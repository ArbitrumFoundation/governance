## Governance Action Lifecycle: Example

### Overview

The following describes the steps involved in a "typical" governance execution; i.e., a governance action on L2 that goes through the permissionless governance process (with no actions performed by the security council.)

The execution is initially proposed on layer 2 and takes a "round trip"; i.e., a message is passed down to layer 1 and then another back up to layer 2 where it is ultimately executed. This round-trip exists to enforce the required delay period between a proposal passing and its execution. For rationale, see the Governance Constitution.

### Pre-Governance Steps

We start with some L2 operation executable only by the Arbitrum DAO governance process. To restrict an operation's affordance to the governance, it should require that it can only be performed by the `UpgradeExecutor` contract. I.e.,

We assume this operation in question is call setVersion on the example contract:

```sol
contract UpgradeMe {
    string version = "1";
    address upgradeExecutor = address(123); // address of UpgradeExecutor

    function setVersion(string memory _version) external {
        require(msg.sender == upgradeExecutor, "only from  UpgradeExecutor");
        version = _version;
    }
}
```

We deploy a one-time use contract which will (eventually) execute the operation. Note that this contract will be executed via a delegateCall, and thus should not access any local state:

```sol
contract OneOffUpgradeContract {
    function executeUpgrade() external {
        address upgradeMe = address(456);
        UpgradeMe(upgradeMe).setVersion("2");
    }
}
```

### Governance Action Steps

A total of 6 external contract calls are required to complete the full process. All calls are permissionless. (We include several relevant internal calls as well, though the list of internal calls is not comprehensive):

**On L2**

1. **`L2ArbitrumGovernor.propose`**:

_This call includes severals layers of nested data encoding parameters for steps that follow; we will describe them as we go. The proposal is voted on by governance; only if it passes do we continue_.

2. **`L2ArbitrumGovernor.execute`**

- a. _Internal:_ `ArbitrumTimelock.schedule`


3.**`ArbitrumTimelock.execute`**

_Steps 1 through 3 are all methods inheritted from Open Zeppelin Governer/Timelock contracts & extensions (for submitted a proposal, voting on it, and executing it after a set time delay if it passes). The only custom functionality is that votes delegated to a special reserved address are excluded from the required quorum threshold (See `L2ArbitrumGovernor.quorum`)._

- b. _Internal:_ `ArbSys.sendTxToL1`

_In step 3's execution, calldata is unwrapped to execute a call to Arbitrum's core ArbSys precompile to initiate an L2 to L1 Message; we proceed once the message is confirmed (typically ~1 week later on Arbitrum One)_.

**On L1**:

4. **Outbox.executeTransaction**

- a. _Internal_: bridge.executeCall

_Steps 4 and 4a use Arbitrum core bridge contracts for executing an L2 to L1 message._

- b. _Internal_: `L1ArbitrumTimelock.schedule`

_Step 4b calls a method inherited from Open Zeppelin's timelock contract with a modifier to ensure it's callable only as a cross-chain message initiated by the L2 timelock._

5. **`L1ArbitrumTimelock.execute`**

- a. _Internal_: `Inbox.createRetryableTicket`

_In step 5, we further unwrap the calldata to find that our call is an L1 to L2 message; Arbitrum core Inbox contract is called to send a message back to L2._

**Back on L2**

6. **`UpgradeExecutor.execute`**

- a. _Internal_: `UpgradeExecutor` --> `OneOffUpgradeContract.delegateCall`

_The retryable ticket is "redeemed" to call the final execute method. `execute` further unwraps the calldata to delegate-call to a deployed upgrade contract, in this case, `OneOffUpgradeContract.executeUpgrade`_. With that, our governance action is complete.

### Alterative Paths

##### L1 Governance Action

If the goal is to execute an operation on L1 (i.e., updating an L1 core contract), calldata provided in step 5 can trigger an arbitrary L1 contract call instead of creating a retryable ticket.

##### Security Council: L1 Emergency

The security council multisig can call `L1ArbitrumTimelock.execute` (step 5) directly with a 9 or 12 threshold.

##### Security Council: Non-time-sensitive Critical Upgrade

The security council multisig can call `ArbitrumTimelock.schedule` (step 2a)  directly with a threshold of 7 of 12.

##### Security Council: L2 Emergency

The security council multisig can call `UpgradeExecutor.execute` (step 5) directly with a 9 or 12 threshold.
