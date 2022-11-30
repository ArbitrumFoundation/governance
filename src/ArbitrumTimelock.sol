// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/// @title  Timelock to be used in Arbitrum governance
/// @dev    This contract adds no other functionality to the TimelockControllerUpgradeable
///         other than the ability to initialize it. TimelockControllerUpgradeable has no
///         public methods for this
contract ArbitrumTimelock is TimelockControllerUpgradeable {
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialise the timelock
    /// @param minDelay The minimum amount of delay enforced by this timelock
    /// @param proposers The accounts allowed to propose actions
    /// @param executors The accounts allowed to execute action
    function initialize(uint256 minDelay, address[] memory proposers, address[] memory executors)
        external
        initializer
    {
        __TimelockController_init(minDelay, proposers, executors);
    }
}
