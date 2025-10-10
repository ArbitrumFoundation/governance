// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUpgradeAction} from "./ProxyUpgradeAction.sol";

/// @title MultiProxyUpgradeAction
/// @notice A contract to proxy upgrade the Core and Treasury Governor contracts.
/// @custom:security-contact https://immunefi.com/bug-bounty/arbitrum/information/
contract MultiProxyUpgradeAction is ProxyUpgradeAction {
    /// @notice The address of the Proxy Admin contract.
    address public immutable PROXY_ADMIN;
    /// @notice The address of the current Core Governor contract.
    address public immutable CORE_GOVERNOR_ADDRESS;
    /// @notice The address of the current Treasury Governor contract.
    address public immutable TREASURY_GOVERNOR_ADDRESS;
    /// @notice The address of the new Governor implementation contract.
    address public immutable NEW_GOVERNOR_IMPLEMENTATION_ADDRESS;

    /// @notice Sets up the contract with the given parameters.
    /// @param _proxyAdmin The address of the Proxy Admin contract.
    /// @param _coreGovernorAddress The address of the current Core Governor contract.
    /// @param _treasuryGovernorAddress The address of the current Treasury Governor contract.
    /// @param _newGovernorImplementationAddress The address of the new Governor implementation contract.
    constructor(
        address _proxyAdmin,
        address _coreGovernorAddress,
        address _treasuryGovernorAddress,
        address _newGovernorImplementationAddress
    ) {
        if (
            _proxyAdmin == address(0) || _coreGovernorAddress == address(0)
                || _treasuryGovernorAddress == address(0)
                || _newGovernorImplementationAddress == address(0)
        ) {
            revert("MultiProxyUpgradeAction: zero address");
        }
        PROXY_ADMIN = _proxyAdmin;
        CORE_GOVERNOR_ADDRESS = _coreGovernorAddress;
        TREASURY_GOVERNOR_ADDRESS = _treasuryGovernorAddress;
        NEW_GOVERNOR_IMPLEMENTATION_ADDRESS = _newGovernorImplementationAddress;
    }

    /// @notice Proxy upgrades the Core and Treasury Governor contracts.
    function perform() external {
        perform(PROXY_ADMIN, payable(CORE_GOVERNOR_ADDRESS), NEW_GOVERNOR_IMPLEMENTATION_ADDRESS);
        perform(
            PROXY_ADMIN, payable(TREASURY_GOVERNOR_ADDRESS), NEW_GOVERNOR_IMPLEMENTATION_ADDRESS
        );
        require(
            ProxyAdmin(payable(PROXY_ADMIN))
                .getProxyImplementation(TransparentUpgradeableProxy(payable(CORE_GOVERNOR_ADDRESS)))
            == NEW_GOVERNOR_IMPLEMENTATION_ADDRESS,
            "MultiProxyUpgradeAction: Core Governor not upgraded"
        );
        require(
            ProxyAdmin(payable(PROXY_ADMIN))
                .getProxyImplementation(
                    TransparentUpgradeableProxy(payable(TREASURY_GOVERNOR_ADDRESS))
                ) == NEW_GOVERNOR_IMPLEMENTATION_ADDRESS,
            "MultiProxyUpgradeAction: Treasury Governor not upgraded"
        );
    }
}
