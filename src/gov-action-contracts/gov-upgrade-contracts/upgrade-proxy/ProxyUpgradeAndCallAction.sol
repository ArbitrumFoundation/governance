// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract ProxyUpgradeAndCallAction {
    function perform(address admin, address payable target, address newLogic, bytes calldata data)
        public
        payable
    {
        ProxyAdmin(admin).upgradeAndCall{value: msg.value}(
            TransparentUpgradeableProxy(target), newLogic, data
        );
    }
}
