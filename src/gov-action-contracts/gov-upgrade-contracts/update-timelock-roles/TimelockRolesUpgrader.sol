// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {TimelockControllerUpgradeable} from
    "openzeppelin-upgradeable-v5/governance/TimelockControllerUpgradeable.sol";

/// @title TimelockRolesUpgrader
/// @notice A contract to upgrade the proposer and canceller roles of the Core and Treasury Governor contracts on the
/// Core and Treasury Timelock
/// @custom:security-contact https://immunefi.com/bug-bounty/arbitrum/information/
contract TimelockRolesUpgrader {
    /// @notice The address of the Core Timelock contract where proposals are queued and executed.
    address public immutable CORE_TIMELOCK;
    /// @notice The address of the current Core Governor contract that has the `PROPOSER_ROLE` and `CANCELLER_ROLE` roles,
    /// which will be revoked.
    address public immutable CURRENT_CORE_GOVERNOR;
    /// @notice The address of the new Core Governor contract that will have the `PROPOSER_ROLE` and `CANCELLER_ROLE`
    /// roles.
    address public immutable NEW_CORE_GOVERNOR;
    /// @notice The address of the Treasury Timelock contract where proposals are queued and executed.
    address public immutable TREASURY_TIMELOCK;
    /// @notice The address of the current Treasury Governor contract that has the `PROPOSER_ROLE` and `CANCELLER_ROLE`
    /// roles, which will be revoked.
    address public immutable CURRENT_TREASURY_GOVERNOR;
    /// @notice The address of the new Treasury Governor contract that will have the `PROPOSER_ROLE` and `CANCELLER_ROLE`
    /// roles.
    address public immutable NEW_TREASURY_GOVERNOR;

    /// @notice Sets up the contract with the given parameters.
    /// @param _coreTimelock The address of the Core Timelock contract.
    /// @param _currentCoreGovernor The address of the current Core Governor contract.
    /// @param _newCoreGovernor The address of the new Core Governor contract.
    /// @param _treasuryTimelock The address of the Treasury Timelock contract.
    /// @param _currentTreasuryGovernor The address of the current Treasury Governor contract.
    /// @param _newTreasuryGovernor The address of the new Treasury Governor contract.
    constructor(
        address _coreTimelock,
        address _currentCoreGovernor,
        address _newCoreGovernor,
        address _treasuryTimelock,
        address _currentTreasuryGovernor,
        address _newTreasuryGovernor
    ) {
        if (
            _coreTimelock == address(0) || _currentCoreGovernor == address(0)
                || _newCoreGovernor == address(0) || _treasuryTimelock == address(0)
                || _currentTreasuryGovernor == address(0) || _newTreasuryGovernor == address(0)
        ) {
            revert("TimelockRolesUpgrader: zero address");
        }
        CORE_TIMELOCK = _coreTimelock;
        TREASURY_TIMELOCK = _treasuryTimelock;
        CURRENT_CORE_GOVERNOR = _currentCoreGovernor;
        NEW_CORE_GOVERNOR = _newCoreGovernor;
        CURRENT_TREASURY_GOVERNOR = _currentTreasuryGovernor;
        NEW_TREASURY_GOVERNOR = _newTreasuryGovernor;
    }

    // @notice Swaps the `PROPOSER_ROLE` and `CANCELLER_ROLE` roles of the old Core Governor and Treasury Governor
    // contracts on the Timelock contract to new Core and Treasury governor contracts.
    function perform() external {
        _swapGovernorsOnTimelock(CORE_TIMELOCK, CURRENT_CORE_GOVERNOR, NEW_CORE_GOVERNOR);
        _swapGovernorsOnTimelock(
            TREASURY_TIMELOCK, CURRENT_TREASURY_GOVERNOR, NEW_TREASURY_GOVERNOR
        );
    }

    // @dev Grants `PROPOSER_ROLE` and `CANCELLER_ROLE` roles on the Timelock contract to a single new governor and
    // Revokes the roles from the old governor.
    // @param _timelock The address of the Timelock contract.
    // @param _oldGovernor The address of the current governor.
    // @param _newGovernor The address of the new governor.
    function _swapGovernorsOnTimelock(address _timelock, address _oldGovernor, address _newGovernor)
        private
    {
        _grantRole(_timelock, _newGovernor, keccak256("PROPOSER_ROLE"));
        _grantRole(_timelock, _newGovernor, keccak256("CANCELLER_ROLE"));
        _revokeRole(_timelock, _oldGovernor, keccak256("PROPOSER_ROLE"));
        _revokeRole(_timelock, _oldGovernor, keccak256("CANCELLER_ROLE"));

        // Check roles were changed
        TimelockControllerUpgradeable timelock = TimelockControllerUpgradeable(payable(_timelock));
        require(
            timelock.hasRole(keccak256("PROPOSER_ROLE"), _newGovernor),
            "PROPOSER_ROLE role not granted"
        );
        require(
            timelock.hasRole(keccak256("CANCELLER_ROLE"), _newGovernor),
            "CANCELLER_ROLE role not granted"
        );
        require(
            !timelock.hasRole(keccak256("PROPOSER_ROLE"), _oldGovernor),
            "PROPOSER_ROLE role not revoked"
        );
        require(
            !timelock.hasRole(keccak256("CANCELLER_ROLE"), _oldGovernor),
            "CANCELLER_ROLE role not revoked"
        );
    }

    /// @dev Grants a role to a governor on a Timelock contract.
    /// @param _timelock The address of the Timelock contract.
    /// @param _governor The address of the governor being granted the role.
    /// @param _role The role to grant.
    function _grantRole(address _timelock, address _governor, bytes32 _role) private {
        TimelockControllerUpgradeable(payable(_timelock)).grantRole(_role, _governor);
    }

    /// @dev Revokes a role from a governor on a Timelock contract.
    /// @param _timelock The address of the Timelock contract.
    /// @param _governor The address of the governor being revoked the role.
    /// @param _role The role to revoke.
    function _revokeRole(address _timelock, address _governor, bytes32 _role) private {
        TimelockControllerUpgradeable(payable(_timelock)).revokeRole(_role, _governor);
    }
}
