// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

library SecurityCouncilMgmtUtils {
    function copyAddressArray(address[] memory source) public pure returns (address[] memory) {
        uint256 length = source.length;
        address[] memory destination = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            destination[i] = source[i];
        }

        return destination;
    }

    function isInArray(address addr, address[] memory arr) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == addr) {
                return true;
            }
        }
        return false;
    }

    function removeSharedAddresses(address[] memory arr1, address[] memory arr2)
        external
        returns (address[] memory newArr1, address[] memory newArr2)
    {
        address[] memory newArr1;
        address[] memory newArr2;
        for (uint256 i = 0; i < arr1.length; i++) {
            address currentAddress = arr1[i];
            if (!isInArray(currentAddress, arr2)) {
                newArr1[newArr1.length] = arr1[i];
            }
        }
        for (uint256 i = 0; i < arr2.length; i++) {
            address currentAddress = arr2[i];
            if (!isInArray(currentAddress, arr1)) {
                newArr2[newArr2.length] = arr2[i];
            }
        }
    }
}
