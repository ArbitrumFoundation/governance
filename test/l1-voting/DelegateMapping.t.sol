// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {DelegateMapping} from "../../src/l1-voting/DelegateMapping.sol";

contract DelegateMappingTest is Test {
    event Claimed(address indexed account, address indexed claimedAccount);

    DelegateMapping delegateMapping;
    address alice = address(0xA11CE);

    function setUp() public {
        delegateMapping = new DelegateMapping();
    }

    function testClaimSetsClaimAndEmits() public {
        vm.expectEmit();
        emit Claimed(alice, address(0xDE1));
        vm.prank(alice);
        delegateMapping.claim(address(0xDE1));
        assertEq(delegateMapping.claimed(alice), address(0xDE1));
    }

    function testReclaimOverwrites() public {
        vm.startPrank(alice);
        delegateMapping.claim(address(0xDE1));
        delegateMapping.claim(address(0xDE2));
        vm.stopPrank();
        assertEq(delegateMapping.claimed(alice), address(0xDE2));
    }

    function testClaimZeroRevokes() public {
        vm.startPrank(alice);
        delegateMapping.claim(address(0xDE1));
        delegateMapping.claim(address(0));
        vm.stopPrank();
        assertEq(delegateMapping.claimed(alice), address(0));
    }
}
