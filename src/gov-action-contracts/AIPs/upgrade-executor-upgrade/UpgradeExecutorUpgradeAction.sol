// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {UpgradeExecutor} from "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";

import {
    ProxyAdmin,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {ERC1967Upgrade} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

contract UpgradeExecutorUpgradeAction is ERC1967Upgrade {
    address public immutable newUpgradeExecutorImplementation = address(new UpgradeExecutor());

    function perform() external {
        ProxyAdmin proxyAdmin = ProxyAdmin(_getAdmin());
        TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(address(this)));

        ProxyAdmin(proxyAdmin).upgrade(proxy, newUpgradeExecutorImplementation);

        require(
            ProxyAdmin(proxyAdmin).getProxyImplementation(proxy) == newUpgradeExecutorImplementation,
            "UpgradeExecutorUpgradeAction: upgrade failed"
        );
    }
}
