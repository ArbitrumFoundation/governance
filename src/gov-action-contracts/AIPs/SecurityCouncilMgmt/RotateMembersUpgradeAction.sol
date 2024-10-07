// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../address-registries/L2AddressRegistryInterfaces.sol";
import "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";

/// @notice Upgrades the sec council manager to allow member rotation and sets min rotation vars
contract RotateMembersUpgradeAction {
    IL2AddressRegistry public immutable l2AddressRegistry;
    address public immutable secCouncilManagerImpl;
    uint256 public immutable minRotationPeriod;
    address public immutable minRotationPeriodSetter;
    
    constructor(IL2AddressRegistry _l2AddressRegistry, address _secCouncilManagerImpl, uint256 _minRotationPeriod, address _minRotationPeriodSetter) {
        l2AddressRegistry = _l2AddressRegistry;
        secCouncilManagerImpl = _secCouncilManagerImpl;
        minRotationPeriod = _minRotationPeriod;
        minRotationPeriodSetter = _minRotationPeriodSetter;
    }

    function perform() external {
        ISecurityCouncilManager secCouncilManager = l2AddressRegistry.securityCouncilManager();
        l2AddressRegistry.govProxyAdmin().upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(secCouncilManager))),
            secCouncilManagerImpl,
            abi.encodeCall(ISecurityCouncilManager(secCouncilManagerImpl).postUpgradeInit, (minRotationPeriod, minRotationPeriodSetter))
        );

        require(minRotationPeriod == secCouncilManager.minRotationPeriod(), "RotateMembersUpgradeAction: Min rotation period not set");
        require(IAccessControlUpgradeable(address(secCouncilManager)).hasRole(secCouncilManager.MIN_ROTATION_PERIOD_SETTER_ROLE(), minRotationPeriodSetter), "RotateMembersUpgradeAction: Min rotation period setter not set");
    }
}