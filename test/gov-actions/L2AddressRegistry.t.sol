// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../util/ActionTestBase.sol";

contract L2AddressRegistryTest is Test, ActionTestBase {
    function testAddressRegistryAddress() public {
        assertEq(
            address(arbOneAddressRegistry.coreGov()),
            address(coreGov),
            "Invalid coreGov gov address"
        );
        assertEq(
            address(arbOneAddressRegistry.treasuryGov()),
            address(treasuryGov),
            "Invalid treasuryGov address"
        );

        assertEq(
            address(arbOneAddressRegistry.treasuryWallet()),
            address(treasuryWallet),
            "Invalid treasuryWallet address"
        );

        assertEq(
            address(arbOneAddressRegistry.arbitrumDAOConstitution()),
            address(arbitrumDAOConstitution),
            "Invalid arbitrumDAOConstitution address"
        );

        assertEq(
            address(arbOneAddressRegistry.coreGovTimelock()),
            address(coreTimelock),
            "Invalid coreTimelock address"
        );

        assertEq(
            address(arbOneAddressRegistry.treasuryGovTimelock()),
            address(treasuryTimelock),
            "Invalid treasuryTimelock address"
        );

        assertEq(
            address(arbOneAddressRegistry.l2ArbitrumToken()),
            address(arbOneToken),
            "Invalid arbOneToken address"
        );
    }
}
