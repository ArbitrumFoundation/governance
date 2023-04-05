// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/ArbitrumFoundationVestingWallet.sol";
import "../src/L2ArbitrumToken.sol";
import "../src/L2ArbitrumGovernor.sol";
import "../src/ArbitrumTimelock.sol";
import "../src/Util.sol";

import "./util/TestUtil.sol";

import "forge-std/Test.sol";

contract ArbitrumFoundationVestingWalletTest is Test {
    address beneficiary = address(1111);

    uint64 startTime = 1000;
    uint64 duration = 1000;
    address arbitrumGoverner;
    address vestingWalletOwner = address(1112);

    uint256 initialSupply = 10 * 1_000_000_000 * (10 ** 18);
    address tokenOwner = address(1113);
    address rando = address(1114);
    uint256 initialFundingAmount = 1000;
    address newBeneficary = address(11_116);

    function deployAndInit()
        public
        returns (ArbitrumFoundationVestingWallet, L2ArbitrumToken, L2ArbitrumGovernor)
    {
        L2ArbitrumToken token =
            L2ArbitrumToken(TestUtil.deployProxy(address(new L2ArbitrumToken())));
        token.initialize(address(1115), initialSupply, tokenOwner);

        ArbitrumTimelock timelock =
            ArbitrumTimelock(payable(TestUtil.deployProxy(address(new ArbitrumTimelock()))));

        L2ArbitrumGovernor l2ArbitrumGovernor =
            L2ArbitrumGovernor(payable(TestUtil.deployProxy(address(new L2ArbitrumGovernor()))));
        l2ArbitrumGovernor.initialize(token, timelock, address(0), 1, 1, 1, 1, 1);

        ArbitrumFoundationVestingWallet foundaitonVestingWallet = ArbitrumFoundationVestingWallet(
            payable(TestUtil.deployProxy(address(new ArbitrumFoundationVestingWallet())))
        );
        foundaitonVestingWallet.initialize(
            beneficiary, startTime, duration, address(l2ArbitrumGovernor), vestingWalletOwner
        );

        vm.startPrank(tokenOwner);
        token.transfer(address(foundaitonVestingWallet), initialFundingAmount);
        vm.stopPrank();
        return (foundaitonVestingWallet, token, l2ArbitrumGovernor);
    }

    function testProperlyInits() external {
        (
            ArbitrumFoundationVestingWallet foundaitonVestingWallet,
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov
        ) = deployAndInit();
        assertEq(foundaitonVestingWallet.start(), startTime, "Start time set");
        assertEq(foundaitonVestingWallet.duration(), duration, "Duration set");
        assertEq(foundaitonVestingWallet.beneficiary(), beneficiary, "beneficiary set");
        assertEq(foundaitonVestingWallet.owner(), vestingWalletOwner, "Owner set");
        assertEq(
            token.delegates(address(foundaitonVestingWallet)),
            gov.EXCLUDE_ADDRESS(),
            "Delegates to exclude address"
        );
        assertEq(
            token.balanceOf(address(foundaitonVestingWallet)),
            initialFundingAmount,
            "wallet is funded"
        );

        vm.expectRevert("Initializable: contract is already initialized");
        foundaitonVestingWallet.initialize(
            beneficiary, startTime, duration, address(gov), vestingWalletOwner
        );
    }

    function testOnlyOwnerCanSetBeneficiary() external {
        (
            ArbitrumFoundationVestingWallet foundaitonVestingWallet,
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov
        ) = deployAndInit();
        assertEq(foundaitonVestingWallet.beneficiary(), beneficiary, "beneficiary set");

        vm.startPrank(vestingWalletOwner);
        foundaitonVestingWallet.setBeneficiary(newBeneficary);
        assertEq(foundaitonVestingWallet.beneficiary(), newBeneficary, "new beneficiary set");
        vm.stopPrank();
    }

    function testOwnlyOwnerCanSetBeneficiary() external {
        (
            ArbitrumFoundationVestingWallet foundaitonVestingWallet,
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov
        ) = deployAndInit();

        vm.startPrank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        foundaitonVestingWallet.setBeneficiary(address(newBeneficary));
        vm.stopPrank();
    }

    function testRelease() external {
        (
            ArbitrumFoundationVestingWallet foundaitonVestingWallet,
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov
        ) = deployAndInit();
        assertEq(token.balanceOf(beneficiary), 0, "beneficiary has no tokens");

        // sanity: ensure test env is att a < starttime timestamp
        assertTrue(block.timestamp < startTime, "pre start time");

        vm.startPrank(beneficiary);
        foundaitonVestingWallet.release();
        assertEq(token.balanceOf(beneficiary), 0, "beneficiary still has no tokens");

        vm.warp(1500);

        foundaitonVestingWallet.release(address(token));
        assertEq(token.balanceOf(beneficiary), 500, "beneficiary got tokens");
        vm.stopPrank();

        vm.startPrank(vestingWalletOwner);
        foundaitonVestingWallet.setBeneficiary(newBeneficary);

        vm.warp(1600);
        vm.stopPrank();

        vm.startPrank(newBeneficary);
        foundaitonVestingWallet.release(address(token));

        assertEq(token.balanceOf(newBeneficary), 100, "new beneficiary got tokens");

        assertEq(token.balanceOf(beneficiary), 500, "prev beneficiary didn't get more tokens");
        vm.stopPrank();
    }

    function testOnlyBeneficiaryCanRelease() public {
        (
            ArbitrumFoundationVestingWallet foundaitonVestingWallet,
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov
        ) = deployAndInit();
        vm.startPrank(rando);
        vm.expectRevert("ArbitrumFoundationVestingWallet: not beneficiary");
        foundaitonVestingWallet.release(address(token));
        vm.stopPrank();
    }
}
