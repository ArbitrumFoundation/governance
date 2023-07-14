// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/Util.sol";
import "forge-std/Test.sol";

contract TestContract {
    function myMethod(bytes memory someParam) external {}
}

contract UtilTest is Test {
    bytes bytesData = bytes("0x123");
    bytes calldataWithSelector = abi.encodeWithSelector(TestContract.myMethod.selector, bytesData);

    function testGetSelector() public {
        assertEq(
            getSelector(calldataWithSelector), TestContract.myMethod.selector, "selector retrieved"
        );
    }

    function testRemoveSelector() public {
        assertEq(removeSelector(calldataWithSelector), abi.encode(bytesData), "selector removed");
    }
}
