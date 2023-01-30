# Governance Proposal Lifecycle: Example

## Overview

The following describes the steps involved in a _typical_ governance execution; i.e., a governance action on L2 that goes through the permissionless governance process (with no actions performed by the security council).

The execution is initially proposed on layer 2 and takes a _round trip_; i.e., a message is passed down to layer 1 and then another back up to layer 2 where it is ultimately executed. This round-trip exists to enforce the required delay period between a proposal passing and its execution. For rationale, see the Governance Constitution.

## Pre-Governance Steps

We start with some L2 operation executable only by the Arbitrum DAO governance process. To restrict an operation's affordance to the governance, it should require that it can only be performed by the `UpgradeExecutor` contract. I.e.,

We assume this operation in question is calling `setVersion` on the example contract:

```solidity
contract UpgradeMe {
    string version = "1";
    address upgradeExecutor = address(123); // address of UpgradeExecutor

    function setVersion(string memory _version) external {
        require(msg.sender == upgradeExecutor, "only from  UpgradeExecutor");
        version = _version;
    }
}
```

We deploy a one-time use contract which will (eventually) execute the operation. Note that this contract will be executed via a `delegatecall`, and thus should not access any local state:

```solidity
contract OneOffUpgradeContract {
    function executeUpgrade() external {
        address upgradeMe = address(456);
        UpgradeMe(upgradeMe).setVersion("2");
    }
}
```

## Forming a proposal

To form a proposal we need to work backwards from the `delegatecall` to the upgrade contract made in the executor. Using the example above we'll work through forming a proposal's data, as if it were being executed by the `UpgradeExecutor` on Arbitrum One.

```solidity
interface IUpgradeExecutor {
    function execute(address to, bytes calldata data) payable external;
}
interface IL1Timelock {
    function RETRYABLE_TICKET_MAGIC() external returns(address);
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;
    function getMinDelay() external view returns (uint256);
}
interface IArbSys {
    function sendTxToL1(address destination, bytes calldata data)
        external
        payable
        returns (uint256);
}
interface IL2ArbitrumGovernor {
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);
}


contract ProposalCreatorTest {
    function createProposal(
        address l1TimelockAddr,
        string memory proposalDescription,
        address oneOffUpgradeAddr,
        address arbOneInboxAddr,
        address upgradeExecutorAddr
    ) public {
        address retryableTicketMagic = IL1Timelock(l1TimelockAddr).RETRYABLE_TICKET_MAGIC();
        uint minDelay = IL1Timelock(l1TimelockAddr).getMinDelay();

        // the data to call the upgrade executor with
        // it tells the upgrade executor how to call the upgrade contract, and what calldata to provide to it
        bytes memory upgradeExecutorCallData = abi.encodeWithSelector(IUpgradeExecutor.execute.selector,
            oneOffUpgradeAddr,
            abi.encodeWithSelector(OneOffUpgradeContract.executeUpgrade.selector)
        );

        // the data provided to call the l1 timelock with
        // specifies how to create a retryable ticket, which will then be used to call the upgrade executor with the
        // data created from the step above
        bytes memory l1TimelockData = abi.encodeWithSelector(IL1Timelock.schedule.selector,
            retryableTicketMagic, // tells the l1 timelock that we want to make a retryable, instead of an l1 upgrade
            0, // ignored for l2 upgrades
            abi.encode( // these are the retryable data params
                arbOneInboxAddr, // the inbox we want to use, should be arb one or nova inbox
                upgradeExecutorAddr, // the upgrade executor on the l2 network
                0, // no value in this upgrade
                0, // max gas - will be filled in when the retryable is actually executed
                0, // max fee per gas - will be filled in when the retryable is actually executed
                upgradeExecutorCallData // call data created in the previous step
            ),
            bytes32(0), // no predecessor
            keccak256(abi.encodePacked(proposalDescription)), // prop description
            minDelay // delay for this proposal
        );

        // the data provided to the L2 Arbitrum Governor in the propose() method
        // the target will be the ArbSys address on Arb One
        bytes memory proposal = abi.encodeWithSelector(IArbSys.sendTxToL1.selector,  // the execution of the proposal will create an L2->L1 cross chain message
            l1TimelockAddr, // the target of the cross chain message is the L1 timelock
            l1TimelockData // call the l1 timelock with the data created in the previous step
        );
    }
}
```

## Governance Action Steps

After the proposal has been created it goes through a number of stages, each of which requires a user to trigger a transaction:

### **1. ArbOne: `L2ArbitrumGovernor.propose`**

Provided with the data created above. The proposal is voted on by governance; only if it passes do we continue.

### **2. ArbOne: `L2ArbitrumGovernor.queue`**

After the proposal has passed, anyone can send a transaction that calls the `queue` method. This will internally call the `schedule` function on the L2 timelock.

### **3. ArbOne: `ArbitrumTimelock.execute`**

After the timelock delay has passed, anyone can call `execute` on the timelock. Doing so calls the proposal target with the proposal data, which in our case will be the ArbSys precompile, with proposal data as shown in the [Forming a proposal](#forming-a-proposal) section above. Doing so will create an L2->L1 message, which will then need to be executed on L1.

### **4. L1: `Outbox.executeTransaction`**

After waiting for the challenge period to elapse, anyone can execute the L2->L1 message in the L1 Outbox. Doing so will call the address with the `to` address and data provided to ArbSys. In our example above, this would be the L1 Timelock, with the L1 timelock data which calls `L1ArbitrumTimelock.schedule`.

### **5. L1: `L1ArbitrumTimelock.execute`**

After the L2 timelock delay has elapsed, anyone can call the `execute` function to continue. Doing so decodes the retryable data params encoded in the calldata, and calls the inbox to create a retryable ticket whose target is the upgrade executor.

### **6. ArbOne: `UpgradeExecutor.execute`**

Once the retryable ticket has been created, anyone can redeem it, which will call the `execute` function on the upgrade executor. As we've seen above, the upgrade executor will take the data provided and use it to `delegatecall` an upgrade contract to execute the upgrade. In our example, this would be the `OneOffUpgradeContract.executeUpgrade` function.

## Alternative Paths

### L1 Governance Action

If the goal is to execute an operation on L1 (i.e., updating an L1 core contract), calldata provided in step 5 can trigger an arbitrary L1 contract call instead of creating a retryable ticket.

### Security Council: Arbitrum One Emergency

The security council with a 9 of 12 multisig threshold can directly call the Arbitrum One upgrade executor to make an upgrade.

### Security Council: Arbitrum Nova Emergency

The security council with a 9 of 12 multisig threshold can directly call the Arbitrum Nova upgrade executor to make an upgrade.

### Security Council: L1 Emergency

The security council with a 9 of 12 multisig threshold can directly call the L1 upgrade executor to make an upgrade.

### Security Council: Non-time-sensitive Critical Upgrade

The security council with a 7 of 12 multisig threshold can call `ArbitrumTimelock.schedule` on the Arbitrum One timelock, without requiring a governance vote.
