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
    address vestingWalletOwner;

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

        ArbitrumFoundationVestingWallet foundationVestingWallet = ArbitrumFoundationVestingWallet(
            payable(TestUtil.deployProxy(address(new ArbitrumFoundationVestingWallet())))
        );
        foundationVestingWallet.initialize(
            beneficiary, startTime, duration, address(l2ArbitrumGovernor)
        );
        vestingWalletOwner = foundationVestingWallet.owner();

        vm.prank(tokenOwner);
        token.transfer(address(foundationVestingWallet), initialFundingAmount);
        return (foundationVestingWallet, token, l2ArbitrumGovernor);
    }

    function testProperlyInits() external {
        (
            ArbitrumFoundationVestingWallet foundationVestingWallet,
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov
        ) = deployAndInit();
        assertEq(foundationVestingWallet.start(), startTime, "Start time set");
        assertEq(foundationVestingWallet.duration(), duration, "Duration set");
        assertEq(foundationVestingWallet.beneficiary(), beneficiary, "beneficiary set");
        assertEq(gov.owner(), vestingWalletOwner, "Owner set to gov owner");
        assertEq(
            token.delegates(address(foundationVestingWallet)),
            gov.EXCLUDE_ADDRESS(),
            "Delegates to exclude address"
        );
        assertEq(
            token.balanceOf(address(foundationVestingWallet)),
            initialFundingAmount,
            "wallet is funded"
        );

        vm.expectRevert("Initializable: contract is already initialized");
        foundationVestingWallet.initialize(beneficiary, startTime, duration, address(gov));
    }

    function testOwnerCanSetBeneficiary() external {
        (ArbitrumFoundationVestingWallet foundationVestingWallet,,) = deployAndInit();
        assertEq(foundationVestingWallet.beneficiary(), beneficiary, "beneficiary set");

        vm.prank(vestingWalletOwner);
        foundationVestingWallet.setBeneficiary(newBeneficary);
        assertEq(foundationVestingWallet.beneficiary(), newBeneficary, "new beneficiary set");
    }

    function testBeneficiaryCanSetBeneficiary() external {
        (ArbitrumFoundationVestingWallet foundationVestingWallet,,) = deployAndInit();
        assertEq(foundationVestingWallet.beneficiary(), beneficiary, "beneficiary set");

        vm.prank(beneficiary);
        foundationVestingWallet.setBeneficiary(newBeneficary);
        assertEq(foundationVestingWallet.beneficiary(), newBeneficary, "new beneficiary set");
    }

    function testRandomAddressCantSetBeneficiary() external {
        (ArbitrumFoundationVestingWallet foundationVestingWallet,,) = deployAndInit();

        vm.prank(rando);
        vm.expectRevert("ArbitrumFoundationVestingWallet: caller is not beneficiary or owner");
        foundationVestingWallet.setBeneficiary(address(newBeneficary));
    }

    function testRelease() external {
        (ArbitrumFoundationVestingWallet foundationVestingWallet, L2ArbitrumToken token,) =
            deployAndInit();
        assertEq(token.balanceOf(beneficiary), 0, "beneficiary has no tokens");

        // sanity: ensure test env is att a < starttime timestamp
        assertTrue(block.timestamp < startTime, "pre start time");

        vm.startPrank(beneficiary);
        foundationVestingWallet.release();
        assertEq(token.balanceOf(beneficiary), 0, "beneficiary still has no tokens");

        vm.warp(1500);

        foundationVestingWallet.release(address(token));
        assertEq(token.balanceOf(beneficiary), 500, "beneficiary got tokens");
        vm.stopPrank();

        vm.prank(vestingWalletOwner);
        foundationVestingWallet.setBeneficiary(newBeneficary);

        vm.warp(1600);

        vm.prank(newBeneficary);
        foundationVestingWallet.release(address(token));

        assertEq(token.balanceOf(newBeneficary), 100, "new beneficiary got tokens");

        assertEq(token.balanceOf(beneficiary), 500, "prev beneficiary didn't get more tokens");
    }

    function testOnlyBeneficiaryCanRelease() public {
        (ArbitrumFoundationVestingWallet foundationVestingWallet, L2ArbitrumToken token,) =
            deployAndInit();
        vm.prank(rando);
        vm.expectRevert("ArbitrumFoundationVestingWallet: not beneficiary");
        foundationVestingWallet.release(address(token));
    }

    function testOnlyOwnerCanMigrate() public {
        (ArbitrumFoundationVestingWallet foundationVestingWallet, L2ArbitrumToken token,) =
            deployAndInit();
        vm.startPrank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        foundationVestingWallet.migrateTokensToNewWallet(address(token), rando);

        vm.expectRevert("Ownable: caller is not the owner");
        foundationVestingWallet.migrateEthToNewWallet(rando);
    }

    function testMigrationTargetMustBeContract() public {
        (ArbitrumFoundationVestingWallet foundationVestingWallet, L2ArbitrumToken token,) =
            deployAndInit();
        vm.startPrank(vestingWalletOwner);

        vm.expectRevert("ArbitrumFoundationVestingWallet: new wallet must be a contract");
        foundationVestingWallet.migrateTokensToNewWallet(address(token), rando);

        vm.expectRevert("ArbitrumFoundationVestingWallet: new wallet must be a contract");
        foundationVestingWallet.migrateEthToNewWallet(rando);

        vm.stopPrank();
    }

    function testMigrateTokensToNewWalletWithSlowerVesting() public {
        (
            ArbitrumFoundationVestingWallet foundationVestingWallet,
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov
        ) = deployAndInit();

        ArbitrumFoundationVestingWallet newWallet = ArbitrumFoundationVestingWallet(
            payable(TestUtil.deployProxy(address(new ArbitrumFoundationVestingWallet())))
        );
        uint64 newWalletVestingDuration = 100_000;
        newWallet.initialize(beneficiary, startTime, newWalletVestingDuration, address(gov));

        vm.prank(vestingWalletOwner);
        foundationVestingWallet.migrateTokensToNewWallet(address(token), address(newWallet));
        assertEq(token.balanceOf(address(foundationVestingWallet)), 0, "tokens not migrated");
        assertEq(token.balanceOf(address(newWallet)), initialFundingAmount, "tokens not migrated");
    }

    function testMigrateTokensToNewWalletWithFasterVesting() public {
        (
            ArbitrumFoundationVestingWallet foundationVestingWallet,
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov
        ) = deployAndInit();

        ArbitrumFoundationVestingWallet newWallet = ArbitrumFoundationVestingWallet(
            payable(TestUtil.deployProxy(address(new ArbitrumFoundationVestingWallet())))
        );
        uint64 newWalletVestingDuration = 10;
        newWallet.initialize(beneficiary, startTime, newWalletVestingDuration, address(gov));

        vm.prank(vestingWalletOwner);
        foundationVestingWallet.migrateTokensToNewWallet(address(token), address(newWallet));
        assertEq(token.balanceOf(address(foundationVestingWallet)), 0, "tokens not migrated");
        assertEq(token.balanceOf(address(newWallet)), initialFundingAmount, "tokens not migrated");
    }

    function testMigrateEthToNewWalletWithSlowerVesting() public {
        (ArbitrumFoundationVestingWallet foundationVestingWallet,, L2ArbitrumGovernor gov) =
            deployAndInit();

        ArbitrumFoundationVestingWallet newWallet = ArbitrumFoundationVestingWallet(
            payable(TestUtil.deployProxy(address(new ArbitrumFoundationVestingWallet())))
        );
        uint64 newWalletVestingDuration = 100_000;
        newWallet.initialize(beneficiary, startTime, newWalletVestingDuration, address(gov));
        uint256 etherAmount = 1 ether;
        vm.deal(address(foundationVestingWallet), etherAmount);

        vm.prank(vestingWalletOwner);
        foundationVestingWallet.migrateEthToNewWallet(address(newWallet));
        assertEq(address(foundationVestingWallet).balance, 0, "eth not migrated");
        assertEq(address(newWallet).balance, etherAmount, "eth not migrated");
    }
}
