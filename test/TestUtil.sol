// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

// @openzeppelin-contracts-upgradeable-0.8 doesn't contain transparent proxies
import "@openzeppelin/contracts-0.8/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-0.8/proxy/transparent/ProxyAdmin.sol";

function deployProxy(address logic, address proxyAdmin, bytes memory data) returns (address) {
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(logic, proxyAdmin, data);
    return address(proxy);
}

function deployProxy(address logic) returns (address) {
    return deployProxy(logic, address(new ProxyAdmin()), bytes(""));
}
