// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @title  A root contract from which it execute upgrades
/// @notice Does not contain upgrade logic itself, only the means to call upgrade contracts and execute them
/// @dev    We use these upgrade contracts as they allow multiple actions to take place in an upgrade
///         and for these actions to interact. However because we are delegatecalling into these upgrade
///         contracts, it's important that these upgrade contract do not touch or modify contract state.
contract UpgradeExecutor is Initializable, AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    address private initializeCaller;

    constructor() {
        _disableInitializers();
    }

    function preInit(address _initializeCaller) public {
        require(initializeCaller == address(0), "INITIALIZER_SET");
        initializeCaller = _initializeCaller;
    }

    /// @notice Initialise the upgrade executor
    /// @param admin The admin who can update other roles, and itself - ADMIN_ROLE
    /// @param executors Can call the execute function - EXECUTOR_ROLE
    function initialize(address admin, address[] memory executors) public initializer {
        if (initializeCaller != address(0)) {
            require(msg.sender == initializeCaller, "NOT_INITIALIZE_CALLER");
        }
        require(admin != address(0), "UpgradeExecutor: zero admin");

        __AccessControl_init();

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(EXECUTOR_ROLE, ADMIN_ROLE);

        _setupRole(ADMIN_ROLE, admin);
        for (uint256 i = 0; i < executors.length; ++i) {
            _setupRole(EXECUTOR_ROLE, executors[i]);
        }
    }

    /// @notice Execute an upgrade by delegate calling an upgrade contract
    /// @dev    Only executor can call this. Since we're using a delegatecall here the Upgrade contract
    ///         will have access to the state of this contract - including the roles. Only upgrade contracts
    ///         that do not touch local state should be used.
    ///         This call does allow re-entrancy, and again, it's the responsibilty of those writing and
    ///         accepting a specific upgrade contract to vet it for issues like this - this is the same
    ///         assumption as the OZ TimelockController, which also allows re-entrancy.
    function execute(address upgrade, bytes memory upgradeCallData)
        public
        payable
        onlyRole(EXECUTOR_ROLE)
    {
        (bool success,) = address(upgrade).delegatecall(upgradeCallData);
        require(success, "UpgradeExecutor: inner delegate call failed");
    }
}
