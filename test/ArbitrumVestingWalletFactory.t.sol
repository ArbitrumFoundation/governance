// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/ArbitrumVestingWalletFactory.sol";
// import "../src/L2ArbitrumToken.sol";
// import "../src/L2ArbitrumGovernor.sol";
// import "../src/TokenDistributor.sol";
// import "../src/ArbitrumTimelock.sol";
// import "../src/Util.sol";

// import "./util/TestUtil.sol";

import "forge-std/Test.sol";

contract ArbitrumVestingWalletFactoryTest is Test {
    uint256 timestampNow = 5000;
    uint64 startTimestamp = 10_000;
    uint64 duration = startTimestamp * 3;

    function testDeploy() external {
        ArbitrumVestingWalletsFactory fac = new ArbitrumVestingWalletsFactory();
        vm.warp(timestampNow);

        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = address(1);
        beneficiaries[1] = address(2);
        beneficiaries[2] = address(3);

        address[] memory wallets = fac.createWallets(startTimestamp, duration, beneficiaries);
        assertEq(ArbitrumVestingWallet(payable(wallets[0])).beneficiary(), beneficiaries[0], "Beneficiary 0");
    }
}
