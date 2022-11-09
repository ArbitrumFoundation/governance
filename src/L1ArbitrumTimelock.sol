// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "./L1ArbitrumMessenger.sol";

interface IInboxSubmissionFee {
    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee)
        external
        view
        returns (uint256);
}

contract L1ArbitrumTimelock is TimelockControllerUpgradeable, L1ArbitrumMessenger {
    address public inbox;
    address public l2Timelock;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address _inbox,
        address _l2Timelock
    ) external initializer {
        require(_inbox != address(0), "L1ArbitrumTimelock: zero inbox");
        require(_l2Timelock != address(0), "L1ArbitrumTimelock: zero l2 timelock");
        __TimelockController_init(minDelay, proposers, executors);

        inbox = _inbox;
        l2Timelock = _l2Timelock;

        // the bridge is allowed to create proposals
        // and we ensure that the l2 caller is the l2timelock
        // by using the onlyCounterpartTimelock modifier
        address bridge = address(getBridge(_inbox));
        grantRole(PROPOSER_ROLE, bridge);
    }

    modifier onlyCounterpartTimelock() {
        // this bridge == msg.sender check is redundant in all the places that
        // we currently use this modififer  since we call a function on super
        // that also checks the proposer role, which we enforce is in the intializer above
        // so although the msg.sender is being checked against the bridge twice we
        // still leave this check here for consistency of this function and in case
        // onlyCounterpartTimelock is used on other functions without this proposer check
        // in future
        address bridge = address(getBridge(inbox));
        require(msg.sender == bridge, "L1ArbitrumTimelock: not from bridge");

        // the outbox reports that the L2 address of the sender is the counterpart gateway
        address l2ToL1Sender = super.getL2ToL1Sender(inbox);
        require(l2ToL1Sender == l2Timelock, "L1ArbitrumTimelock: not from l2 timelock");
        _;
    }

    /// @notice Schedule actions to be later executed
    /// @dev Only callable by the l2 timelock, via the outbox/bridge
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual override (TimelockControllerUpgradeable) onlyCounterpartTimelock {
        TimelockControllerUpgradeable.scheduleBatch(
            targets, values, payloads, predecessor, salt, delay
        );
    }

    /// @notice Schedule an action to be later executed
    /// @dev Only callable by the l2 timelock, via the outbox/bridge
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual override (TimelockControllerUpgradeable) onlyCounterpartTimelock {
        TimelockControllerUpgradeable.schedule(target, value, data, predecessor, salt, delay);
    }

    /// @dev If the target is the inbox we assume a cross chain call is intended
    //       so instead of executing directly we create a retryable ticket
    function _execute(address target, uint256 value, bytes calldata data)
        internal
        virtual
        override
    {
        if (target == inbox) {
            // if the target is the inbox we assume that the intention was to create a
            // a retryable ticket. This means that the timelock can't actually execute any
            // other methods on the Inbox, but that's ok because non of the admin functions
            // on the Inbox should directly be the timelock.
            // we assume that retryable ticket params were provided in the data
            (
                address l2Target,
                uint256 l2Value,
                address excessFeeRefundAddress,
                address callValueRefundAddress,
                uint256 gasLimit,
                uint256 maxFeePerGas,
                bytes memory l2Calldata
            ) = abi.decode(data, (address, uint256, address, address, uint256, uint256, bytes));

            // submission fee is dependent on base fee, by looking this up here
            // and ensuring we send enough value to cover it we can be sure that
            // a retryable ticket will be created.
            uint256 submissionCost = IInboxSubmissionFee(inbox).calculateRetryableSubmissionFee(
                l2Calldata.length, block.basefee
            );

            // create a retryable ticket
            // note that the "value" argument has been completely ignored and is set based on
            // what is calculated to be required. The msg.sender then needs to supply value to this
            // function to cover the calculated value.
            sendTxToL2CustomRefund(
                inbox,
                l2Target,
                excessFeeRefundAddress,
                callValueRefundAddress,
                submissionCost + l2Value + (maxFeePerGas * gasLimit),
                l2Value,
                L2GasParams({
                    _maxSubmissionCost: submissionCost,
                    _maxGas: gasLimit,
                    _gasPriceBid: maxFeePerGas
                }),
                l2Calldata
            );

            // return any unspent value to the caller
            // it's the responsbility of the sender to ensure they can
            // receive the funds
            address(msg.sender).call{value: address(this).balance}("");
        } else {
            super._execute(target, value, data);
        }
    }
}
