// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../util/ActionTestBase.sol";

contract L1AddressRegistryTest is Test, ActionTestBase {
    function testAddressRegistryAddress() public {
        assertEq(address(addressRegistry.inbox()), address(inbox), "Invalid inbox address");
        assertEq(
            address(addressRegistry.sequencerInbox()),
            address(si),
            "Invalid sequencer inbox address"
        );
        assertEq(address(addressRegistry.bridge()), address(bridge), "Invalid bridge address");
        assertEq(address(addressRegistry.rollup()), address(rollup), "Invalid rollup address");
    }
}
