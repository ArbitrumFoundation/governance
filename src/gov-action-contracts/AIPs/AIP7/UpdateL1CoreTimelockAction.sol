// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../address-registries/L1AddressRegistry.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/// @notice Upgrade implemention of L1ArbitrumTimelock to fix a bug in scheduleBatch function
/// to properly handle batches in which more than one operation
/// creates a retryable ticket. The bug is non-critical since workarounds exist
contract UpdateL1CoreTimelockAction {
    ProxyAdmin public immutable govProxyAdmin;
    L1AddressRegistry public immutable l1AddressRegistry;
    address public immutable newTimelockImplementation;

    constructor(
        ProxyAdmin _govProxyAdmin,
        L1AddressRegistry _11AddressRegistry,
        address _newTimelockImplementation
    ) {
        require(
            Address.isContract(_newTimelockImplementation),
            "UpdateL1CoreTimelockAction: _newTimelockImplementation is contract"
        );
        govProxyAdmin = _govProxyAdmin;
        l1AddressRegistry = _11AddressRegistry;
        newTimelockImplementation = _newTimelockImplementation;
    }

    function perform() public {
        TransparentUpgradeableProxy timelockProxy =
            TransparentUpgradeableProxy(payable(address(l1AddressRegistry.l1Timelock())));
        govProxyAdmin.upgrade(timelockProxy, newTimelockImplementation);

        // verify
        require(
            govProxyAdmin.getProxyImplementation(timelockProxy) == newTimelockImplementation,
            "UpdateL1CoreTimelockAction: new implementation set"
        );
    }
}
