// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {UpgradeExecutor} from "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
import {
    ProxyAdmin,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract UpgradeExecutorUpgradeAction {
    address public immutable newUpgradeExecutorImplementation;
    ProxyAdmin public immutable proxyAdmin;

    constructor(address _proxyAdmin) {
        proxyAdmin = ProxyAdmin(_proxyAdmin);
        newUpgradeExecutorImplementation = address(new UpgradeExecutor());
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
        UpgradeExecutorUpgradeAction(0xdb216562328215E010F819B5aBe947bad4ca961e)
    {}
}

contract NovaUpgradeExecutorUpgradeAction is UpgradeExecutorUpgradeAction {
    constructor()
        UpgradeExecutorUpgradeAction(0xf58eA15B20983116c21b05c876cc8e6CDAe5C2b9)
    {}
}

contract L1UpgradeExecutorUpgradeAction is UpgradeExecutorUpgradeAction {
    constructor()
        UpgradeExecutorUpgradeAction(0x5613AF0474EB9c528A34701A5b1662E3C8FA0678)
    {}
}
