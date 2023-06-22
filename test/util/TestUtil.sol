// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";

library TestUtil {
    function deployProxy(address logic) public returns (address) {
        ProxyAdmin pa = new ProxyAdmin();
        return address(new TransparentUpgradeableProxy(address(logic), address(pa), ""));
    }

    function areAddressArraysEqual(address[] memory array1, address[] memory array2)
        public
        pure
        returns (bool)
    {
        if (array1.length != array2.length) {
            return false;
        }

        for (uint256 i = 0; i < array1.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < array2.length; j++) {
                if (array1[i] == array2[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }

        for (uint256 i = 0; i < array2.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < array1.length; j++) {
                if (array2[i] == array1[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }

        return true;
    }
}
