// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {UpgradeExecutor} from "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol"; // todo: deploy UpgradeExecutor separately
import {
    ProxyAdmin,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract UpgradeExecutorUpgradeAction {
    ProxyAdmin public immutable proxyAdmin;
    address public immutable newUpgradeExecutorImplementation;

    constructor(address _proxyAdmin, address _newUpgradeExecutorImplementation) {
        proxyAdmin = ProxyAdmin(_proxyAdmin);
        newUpgradeExecutorImplementation = _newUpgradeExecutorImplementation;
    }

    function perform() external {
        TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(address(this)));

        proxyAdmin.upgrade(proxy, newUpgradeExecutorImplementation);

        require(
            proxyAdmin.getProxyImplementation(proxy) == newUpgradeExecutorImplementation,
            "UpgradeExecutorUpgradeAction: upgrade failed"
        );
    }
}

// Proxy Admins:
// Arb1: 0xdb216562328215E010F819B5aBe947bad4ca961e
// Nova: 0xf58eA15B20983116c21b05c876cc8e6CDAe5C2b9
// L1:   0x5613AF0474EB9c528A34701A5b1662E3C8FA0678

contract ArbOneUpgradeExecutorUpgradeAction is UpgradeExecutorUpgradeAction {
    constructor()
        UpgradeExecutorUpgradeAction(
            0xdb216562328215E010F819B5aBe947bad4ca961e,
            address(new UpgradeExecutor()) // todo: deploy UpgradeExecutor separately
        )
    {}
}

contract NovaUpgradeExecutorUpgradeAction is UpgradeExecutorUpgradeAction {
    constructor()
        UpgradeExecutorUpgradeAction(
            0xf58eA15B20983116c21b05c876cc8e6CDAe5C2b9,
            address(new UpgradeExecutor()) // todo: deploy UpgradeExecutor separately
        )
    {}
}

contract L1UpgradeExecutorUpgradeAction is UpgradeExecutorUpgradeAction {
    constructor()
        UpgradeExecutorUpgradeAction(
            0x5613AF0474EB9c528A34701A5b1662E3C8FA0678,
            address(new UpgradeExecutor()) // todo: deploy UpgradeExecutor separately
        )
    {}
}
