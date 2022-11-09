// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

// CHRIS: TODO: lets just use proper errors, better where we can
// error InnerCallFailed(bytes reason);

// CHRIS: TODO: would be nice to constrain the execution to also call an execute function on migrating scripts
// CHRIS: TODO: do we want to require succeed here?
// CHRIS: TODO: I think it's important that we do, or we should a provided gas limit to make sure enough has been supplied
// CHRIS: TODO: otherwise someone could execute this with insufficient gas causing the inner call to fail, but the outer would still store the noce

// CHRIS: TODO: do a check that we have payable everywhere - try sending some value round

contract UpgradeExecutor is Initializable, AccessControlUpgradeable {
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_OWNER_ROLE");

    constructor() {
        _disableInitializers();
    }

    function initialize(address[] memory owners) public initializer {
        __AccessControl_init();
        _setRoleAdmin(EXECUTOR_ROLE, EXECUTOR_ROLE);
        for (uint256 i = 0; i < owners.length; ++i) {
            _setupRole(EXECUTOR_ROLE, owners[i]);
        }
    }

    function execute(address to, bytes memory data) public payable onlyRole(EXECUTOR_ROLE) {
        (bool success,) = address(to).delegatecall(data);
        require(success, "UpgradeExecutor: inner delegate call failed");
    }
}
