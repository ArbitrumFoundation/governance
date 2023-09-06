// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";

contract StubContract {}

library TestUtil {
    function deployProxy(address logic) public returns (address) {
        ProxyAdmin pa = new ProxyAdmin();
        return address(new TransparentUpgradeableProxy(address(logic), address(pa), ""));
    }

    function deployStubContract() public returns (address) {
        return address(new StubContract());
    }

    ///@notice assumes each address array has no repeated elements (i.e., as is the enforced for gnosis safe owners)
    function areUniqueAddressArraysEqual(address[] memory array1, address[] memory array2)
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

        return true;
    }

    function randomUint240s(uint256 length, uint256 seed) public pure returns (uint240[] memory) {
        uint240[] memory arr = new uint240[](length);
        for (uint256 i = 0; i < length; i++) {
            arr[i] = uint240(uint256(keccak256(abi.encode(seed, i))));
        }
        return arr;
    }

    function randomAddresses(uint256 length, uint256 seed) public pure returns (address[] memory) {
        uint240[] memory arr = randomUint240s(length, seed);
        address[] memory addresses = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            addresses[i] = address(uint160(arr[i]));
        }
        return addresses;
    }

    function indexOf(address[] memory array, address element) public pure returns (uint256) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) {
                return i;
            }
        }
        return type(uint256).max;
    }
}
