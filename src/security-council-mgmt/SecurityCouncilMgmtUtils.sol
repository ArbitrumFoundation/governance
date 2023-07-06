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

    function randomAddToSet(
        address[] memory pickFrom,
        address[] memory addTo,
        uint256 targetLength,
        uint256 rng
    ) internal pure returns (address[] memory result) {
        result = new address[](targetLength);

        // add what is already in the addTo list
        for (uint256 i = 0; i < addTo.length; i++) {
            result[i] = addTo[i];
        }

        uint256 currentResultLength = addTo.length;
        while (currentResultLength < targetLength) {
            // pick a random index from the pickFrom list
            rng = uint256(keccak256(abi.encodePacked(rng)));
            uint256 index = rng % pickFrom.length;
            address item = pickFrom[index];

            // loop over the result list to make sure we don't have a duplicate
            bool isDup = false;
            for (uint256 i = 0; i < currentResultLength; i++) {
                if (result[i] == item) {
                    isDup = true;
                    break;
                }
            }

            if (!isDup) {
                result[currentResultLength] = item;
                currentResultLength++;
            }
        }
    }
}
