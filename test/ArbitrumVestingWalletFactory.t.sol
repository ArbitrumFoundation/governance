// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/ArbitrumVestingWalletFactory.sol";

import "forge-std/Test.sol";

contract ArbitrumVestingWalletFactoryTest is Test {
    uint256 timestampNow = 5000;
    uint64 startTimestamp = 10_000;
    uint64 duration = startTimestamp * 3;

    function testDeploy() external {
        ArbitrumVestingWalletsFactory fac = new ArbitrumVestingWalletsFactory();
        vm.warp(timestampNow);

        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = address(137);
        beneficiaries[1] = address(237);
        beneficiaries[2] = address(337);

        address[] memory wallets = fac.createWallets(startTimestamp, duration, beneficiaries);
        assertEq(
            ArbitrumVestingWallet(payable(wallets[0])).beneficiary(),
            beneficiaries[0],
            "Beneficiary 0"
        );
    }

    function testOnlyOwnerCanCreateWallets() external {
        ArbitrumVestingWalletsFactory fac = new ArbitrumVestingWalletsFactory();
        address[] memory beneficiaries = new address[](3);

        vm.prank(address(123_456_789));
        vm.expectRevert("Ownable: caller is not the owner");
        fac.createWallets(startTimestamp, duration, beneficiaries);
    }
}
