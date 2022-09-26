// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

// @openzeppelin-contracts-upgradeable-0.8 doesn't contain transparent proxies
import "@openzeppelin/contracts-0.8/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-0.8/proxy/transparent/ProxyAdmin.sol";

library TestUtil {
    function deployProxy(address logic, address proxyAdmin, bytes memory data) internal returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(logic, proxyAdmin, data);
        return address(proxy);
    }

    function deployProxy(address logic) internal returns (address) {
        return deployProxy(logic, address(new ProxyAdmin()), bytes(""));
    }
}
