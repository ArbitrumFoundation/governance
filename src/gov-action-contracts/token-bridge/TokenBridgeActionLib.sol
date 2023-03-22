// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";

library TokenBridgeActionLib {
    function ensureAllContracts(address[] memory addresses) internal view {
        for (uint256 i = 0; i < addresses.length; i++) {
            require(Address.isContract(addresses[i]), "TokenBridgeActionLib: not contract");
        }
    }
}
