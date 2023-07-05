// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../src/security-council-mgmt/SecurityCouncilMgmtUtils.sol";
import "../util/TestUtil.sol";

contract SecurityCouncilMgmtUtilsTests is Test {
    function testIsInArray() public {
        address[] memory arr1 = new address[](0);
        assertFalse(
            SecurityCouncilMgmtUtils.isInArray(address(1), arr1), "isInArray empty array false"
        );
        address[] memory arr2 = new address[](2);
        arr2[0] = address(1);
        arr2[1] = address(2);
        assertTrue(
            SecurityCouncilMgmtUtils.isInArray(address(1), arr2), "isInArray first element true"
        );
        assertTrue(
            SecurityCouncilMgmtUtils.isInArray(address(2), arr2), "isInArray second element true"
        );
        assertFalse(
            SecurityCouncilMgmtUtils.isInArray(address(3), arr2), "isInArray other element false"
        );
    }

    function testCopyAddressArray() public {
        address[] memory emptyArr = new address[](0);
        assertTrue(
            TestUtil.areAddressArraysEqual(
                emptyArr, SecurityCouncilMgmtUtils.copyAddressArray(emptyArr)
            ),
            "copyAddressArray handles empty array"
        );
        address[] memory arr = new address[](3);
        arr[0] = address(1);
        arr[1] = address(2);
        arr[2] = address(3);

        assertTrue(
            TestUtil.areAddressArraysEqual(arr, SecurityCouncilMgmtUtils.copyAddressArray(arr)),
            "copyAddressArray handles array"
        );
    }
}
