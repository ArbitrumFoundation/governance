// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

library SecurityCouncilMgmtUtils {
    function isInArray(address addr, address[] memory arr) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == addr) {
                return true;
            }
        }
        return false;
    }

    // filters an array of addresses by removing any addresses that are in the excludeList
    function filterAddressesWithExcludeList(
        address[] memory input,
        mapping(address => bool) storage excludeList
    ) internal view returns (address[] memory) {
        address[] memory intermediate = new address[](input.length);
        uint256 intermediateLength = 0;

        for (uint256 i = 0; i < input.length; i++) {
            address nominee = input[i];
            if (!excludeList[nominee]) {
                intermediate[intermediateLength] = nominee;
                intermediateLength++;
            }
        }

        address[] memory output = new address[](intermediateLength);
        for (uint256 i = 0; i < intermediateLength; i++) {
            output[i] = intermediate[i];
        }

        return output;
    }
}
