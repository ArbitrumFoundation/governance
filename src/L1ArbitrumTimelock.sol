// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "./L1ArbitrumMessenger.sol";

// CHRIS: TODO: if governance is upgradeable then what about the timelocks?
// CHRIS: TODO: if the timelocks are upgradeable is that ok?

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
        // the outbox reports that the L2 address of the sender is the counterpart gateway
        address l2ToL1Sender = super.getL2ToL1Sender(inbox);
        require(l2ToL1Sender == l2Timelock, "L1ArbitrumTimelock: not from l2 timelock");
        _;
    }

    // CHRIS: TODO: docs on these
    // CHRIS: TODO: i forgot, is this how we're supposed to use inheritance - should we use super?

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

    function _execute(address target, uint256 value, bytes calldata data)
        internal
        virtual
        override
    {
        if (target == inbox) {
            // if the target is the inbox we only allow the creation of retryable ticketss
            (
                address l2Target,
                uint256 l2Value,
                address excessFeeRefundAddress,
                address callValueRefundAddress,
                uint256 gasLimit,
                uint256 maxFeePerGas,
                bytes memory l2Calldata
            ) = abi.decode(data, (address, uint256, address, address, uint256, uint256, bytes));

            uint256 submissionCost = IInboxSubmissionFee(inbox).calculateRetryableSubmissionFee(
                l2Calldata.length, block.basefee
            );

            sendTxToL2CustomRefund(
                inbox,
                l2Target,
                excessFeeRefundAddress,
                callValueRefundAddress,
                msg.value + value,
                l2Value,
                L2GasParams({
                    _maxSubmissionCost: submissionCost,
                    _maxGas: gasLimit,
                    _gasPriceBid: maxFeePerGas
                }),
                l2Calldata
            );

            // return any unspent value to the caller
            // CHRIS: TODO: should we require this?
            (bool success,) = address(msg.sender).call{value: address(this).balance}("");
            // CHRIS: TODO: error message
            require(success, "CALL FAILED");
        } else {
            // CHRIS: TODO: these calls allow re-entrancy...
            super._execute(target, value, data);
        }
    }
}
