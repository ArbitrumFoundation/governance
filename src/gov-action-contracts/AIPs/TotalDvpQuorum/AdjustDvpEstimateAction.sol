// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IArbTokenPostUpgradeInit {
    function adjustInitialTotalDelegationEstimate(int256 initialEstimationErrorAdjustment) external;
}

/// @notice This action is performed some time after ActivateDvpQuorumAction as a separate governance proposal.
///         Its purpose is to adjust the initial total delegation estimate set in ActivateDvpQuorumAction
contract AdjustDvpEstimateAction {
    address public immutable arbTokenProxy;
    int256 public immutable initialEstimationErrorAdjustment;

    constructor(address _arbTokenProxy, int256 _initialEstimationErrorAdjustment) {
        arbTokenProxy = _arbTokenProxy;
        initialEstimationErrorAdjustment = _initialEstimationErrorAdjustment;
    }

    /// @notice Calls adjustInitialTotalDelegationEstimate on the token contract to adjust the total delegation estimate
    function perform() external {
        IArbTokenPostUpgradeInit(arbTokenProxy).adjustInitialTotalDelegationEstimate(initialEstimationErrorAdjustment);
    }
}
