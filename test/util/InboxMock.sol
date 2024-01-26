// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../src/L1ArbitrumTimelock.sol";

contract InboxMock is IInboxSubmissionFee {
    address l2ToL1SenderMock = address(0);
    uint256 public msgNum = 1;
    address private mbridge;

    constructor(address _bridge) {
        mbridge = _bridge;
    }

    /// @dev msg.value sent to the inbox isn't high enough
    error InsufficientValue(uint256 expected, uint256 actual);

    /// @dev submission cost provided isn't enough to create retryable ticket
    error InsufficientSubmissionCost(uint256 expected, uint256 actual);

    error RetryableData(
        address from,
        address to,
        uint256 l2CallValue,
        uint256 deposit,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        bytes data
    );

    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee)
        public
        view
        returns (uint256)
    {
        // Use current block basefee if baseFee parameter is 0
        return (1400 + 6 * dataLength) * (baseFee == 0 ? block.basefee : baseFee);
    }

    struct RetryableTicket {
        address from;
        address to;
        uint256 l2CallValue;
        uint256 value;
        uint256 maxSubmissionCost;
        address excessFeeRefundAddress;
        address callValueRefundAddress;
        uint256 gasLimit;
        uint256 maxFeePerGas;
        bytes data;
    }

    RetryableTicket[] public retryableTickets;

    function createRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        bytes calldata data
    ) external payable returns (uint256) {
        if (msg.value < (maxSubmissionCost + l2CallValue + gasLimit * maxFeePerGas)) {
            revert InsufficientValue(
                maxSubmissionCost + l2CallValue + gasLimit * maxFeePerGas, msg.value
            );
        }

        if (gasLimit == 1 || maxFeePerGas == 1) {
            revert RetryableData(
                msg.sender,
                to,
                l2CallValue,
                msg.value,
                maxSubmissionCost,
                excessFeeRefundAddress,
                callValueRefundAddress,
                gasLimit,
                maxFeePerGas,
                data
            );
        }

        uint256 submissionFee = calculateRetryableSubmissionFee(data.length, block.basefee);
        if (maxSubmissionCost < submissionFee) {
            revert InsufficientSubmissionCost(submissionFee, maxSubmissionCost);
        }

        retryableTickets.push(
            RetryableTicket({
                from: msg.sender,
                to: to,
                l2CallValue: l2CallValue,
                value: msg.value,
                maxSubmissionCost: maxSubmissionCost,
                excessFeeRefundAddress: excessFeeRefundAddress,
                callValueRefundAddress: callValueRefundAddress,
                gasLimit: gasLimit,
                maxFeePerGas: maxFeePerGas,
                data: data
            })
        );

        return msgNum++;
    }

    function getRetryableTicket(uint256 index) external view returns (RetryableTicket memory) {
        return retryableTickets[index];
    }

    function bridge() external view returns (IBridge) {
        if (mbridge != address(0)) {
            return IBridge(mbridge);
        } else {
            return IBridge(address(this));
        }
    }

    function activeOutbox() external view returns (address) {
        return address(this);
    }

    function setL2ToL1Sender(address sender) external {
        l2ToL1SenderMock = sender;
    }

    function l2ToL1Sender() external view returns (address) {
        return l2ToL1SenderMock;
    }
}
