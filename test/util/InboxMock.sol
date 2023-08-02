// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../src/L1ArbitrumTimelock.sol";

contract InboxMock is IInboxSubmissionFee {
    uint256 public msgNum = 1;
    address public bridge;

    constructor(address _bridge) {
        bridge = _bridge;
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

        return msgNum++;
    }
}
