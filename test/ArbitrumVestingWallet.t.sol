// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/ArbitrumVestingWallet.sol";
import "../src/L2ArbitrumToken.sol";
import "../src/L2ArbitrumGovernor.sol";
import "../src/TokenDistributor.sol";
import "../src/ArbitrumTimelock.sol";
import "../src/Util.sol";

import "./util/TestUtil.sol";

import "forge-std/Test.sol";

contract ArbitrumVestingWalletTest is Test {
    address beneficiary = address(137);
    uint64 secondsPerYear = 60 * 60 * 24 * 365;
    uint64 timestampNow = secondsPerYear;
    uint64 startTimestamp = secondsPerYear * 2; // starts at 2 years
    uint64 durationSeconds = secondsPerYear * 3; // lasts a further 3 years
    uint256 beneficiaryClaim = 200_000_000_000_000;

    uint256 claimPeriodStart = 210;
    uint256 claimPeriodEnd = claimPeriodStart + 20;

    uint256 initialSupply = 10 * 1_000_000_000 * (10 ** 18);
    address l1Token = address(1_234_578);
    address owner = address(12_345_789);
    address payable sweepTo = payable(address(123_457_891));
    address delegatee = address(138);
    address someRando = address(123);
    address tdDelegate = address(127);

    function deployDeps() public returns (L2ArbitrumToken, L2ArbitrumGovernor, TokenDistributor) {
        address token = TestUtil.deployProxy(address(new L2ArbitrumToken()));
        L2ArbitrumToken(token).initialize(l1Token, initialSupply, owner);
        TokenDistributor td = new TokenDistributor(
            IERC20VotesUpgradeable(token),
            sweepTo,
            owner,
            claimPeriodStart,
            claimPeriodEnd,
            tdDelegate
        );
        vm.prank(owner);
        L2ArbitrumToken(token).transfer(address(td), beneficiaryClaim * 2);

        address payable timelock = payable(TestUtil.deployProxy(address(new ArbitrumTimelock())));
        address[] memory proposers;
        address[] memory executors;
        ArbitrumTimelock(timelock).initialize(20, proposers, executors);

        address payable governor = payable(TestUtil.deployProxy(address(new L2ArbitrumGovernor())));
        L2ArbitrumGovernor(governor).initialize(
            IVotesUpgradeable(token),
            ArbitrumTimelock(timelock),
            address(137),
            10_000,
            10_000,
            3,
            0,
            10
        );

        vm.roll(claimPeriodStart);
        vm.warp(timestampNow);

        return (L2ArbitrumToken(token), L2ArbitrumGovernor(governor), td);
    }

    function deploy()
        public
        returns (ArbitrumVestingWallet, L2ArbitrumToken, L2ArbitrumGovernor, TokenDistributor)
    {
        (L2ArbitrumToken token, L2ArbitrumGovernor gov, TokenDistributor td) = deployDeps();
        ArbitrumVestingWallet wallet = new ArbitrumVestingWallet(
            beneficiary,
            startTimestamp,
            durationSeconds
        );

        address[] memory recipients = new address[](1);
        recipients[0] = address(wallet);
        uint256[] memory claims = new uint256[](1);
        claims[0] = beneficiaryClaim;
        vm.prank(owner);
        td.setRecipients(recipients, claims);

        return (wallet, token, gov, td);
    }

    function testDoesDeploy() external {
        (ArbitrumVestingWallet wallet, L2ArbitrumToken token,,) = deploy();

        assertEq(wallet.start(), startTimestamp, "Start time");
        assertEq(wallet.duration(), durationSeconds, "Duration");
        assertEq(wallet.released(address(token)), 0, "Released");
    }

    function testClaim() external {
        (ArbitrumVestingWallet wallet, L2ArbitrumToken token,, TokenDistributor td) = deploy();
        vm.prank(beneficiary);
        wallet.claim(address(td));

        assertEq(token.balanceOf(address(wallet)), beneficiaryClaim, "Claim");
        assertEq(td.claimableTokens(address(wallet)), 0, "Claim left");
    }

    function testClaimFailsForNonBeneficiary() external {
        (ArbitrumVestingWallet wallet,,, TokenDistributor td) = deploy();
        vm.expectRevert("ArbitrumVestingWallet: not beneficiary");
        wallet.claim(address(td));
    }

    function deployAndClaim()
        public
        returns (ArbitrumVestingWallet, L2ArbitrumToken, L2ArbitrumGovernor, TokenDistributor)
    {
        (
            ArbitrumVestingWallet wallet,
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov,
            TokenDistributor td
        ) = deploy();
        vm.prank(beneficiary);
        wallet.claim(address(td));

        return (wallet, token, gov, td);
    }

    function testDelegate() external {
        (ArbitrumVestingWallet wallet, L2ArbitrumToken token,,) = deployAndClaim();

        vm.prank(beneficiary);
        wallet.delegate(address(token), delegatee);

        assertEq(token.delegates(address(wallet)), delegatee, "Delegatee");
    }

    function testDelegateFailsForNonBeneficiary() external {
        (ArbitrumVestingWallet wallet, L2ArbitrumToken token,,) = deployAndClaim();

        vm.expectRevert("ArbitrumVestingWallet: not beneficiary");
        wallet.delegate(address(token), delegatee);
    }

    function deployClaimAndDelegate()
        public
        returns (ArbitrumVestingWallet, L2ArbitrumToken, L2ArbitrumGovernor, TokenDistributor)
    {
        (
            ArbitrumVestingWallet wallet,
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov,
            TokenDistributor td
        ) = deployAndClaim();

        vm.prank(beneficiary);
        wallet.delegate(address(token), delegatee);

        return (wallet, token, gov, td);
    }

    function testCastVote() external {
        (ArbitrumVestingWallet wallet,, L2ArbitrumGovernor gov,) = deployClaimAndDelegate();

        address[] memory targets = new address[](1);
        targets[0] = address(555);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;
        bytes[] memory data = new bytes[](1);
        data[0] = "";

        uint256 propId = gov.propose(targets, amounts, data, "Test prop");
        vm.roll(gov.proposalSnapshot(propId) + 1);

        assertEq(gov.hasVoted(propId, address(wallet)), false, "Has not voted");
        vm.prank(beneficiary);
        wallet.castVote(address(gov), propId, 1);
        assertEq(gov.hasVoted(propId, address(wallet)), true, "Has voted");
    }

    function testCastVoteFailsForNonBeneficiary() external {
        (ArbitrumVestingWallet wallet,, L2ArbitrumGovernor gov,) = deployClaimAndDelegate();

        address[] memory targets = new address[](1);
        targets[0] = address(555);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;
        bytes[] memory data = new bytes[](1);
        data[0] = "";

        uint256 propId = gov.propose(targets, amounts, data, "Test prop");
        vm.roll(gov.proposalSnapshot(propId) + 1);

        assertEq(gov.hasVoted(propId, address(wallet)), false, "Has not voted");
        vm.expectRevert("ArbitrumVestingWallet: not beneficiary");
        wallet.castVote(address(gov), propId, 1);
    }

    uint64 constant SECONDS_PER_YEAR = 60 * 60 * 24 * 365;
    uint64 constant SECONDS_PER_MONTH = SECONDS_PER_YEAR / 12;

    function testVestedAmountStart() external {
        (ArbitrumVestingWallet wallet, L2ArbitrumToken token,,) = deployAndClaim();

        assertEq(wallet.vestedAmount(address(token), startTimestamp - 1), 0, "Vested zero");
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp),
            beneficiaryClaim / 4,
            "Vested cliff"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + 1),
            beneficiaryClaim / 4,
            "Vested cliff after"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_MONTH - 1),
            beneficiaryClaim / 4,
            "Vested one month minus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_MONTH),
            (beneficiaryClaim / 4) + (beneficiaryClaim / 48),
            "Vested at 1 month"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_MONTH + 1),
            (beneficiaryClaim / 4) + (beneficiaryClaim / 48),
            "Vested at 1 month plus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_YEAR - 1),
            (beneficiaryClaim / 4) + ((beneficiaryClaim * 11) / 48),
            "Vested one year minus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_YEAR),
            beneficiaryClaim / 2,
            "Vested one year"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + SECONDS_PER_YEAR + 1),
            beneficiaryClaim / 2,
            "Vested one year plus one"
        );
        assertEq(
            wallet.vestedAmount(
                address(token), startTimestamp + SECONDS_PER_YEAR + SECONDS_PER_MONTH - 1
            ),
            beneficiaryClaim / 2,
            "Vested one year and one month minus one"
        );
        assertEq(
            wallet.vestedAmount(
                address(token), startTimestamp + SECONDS_PER_YEAR + SECONDS_PER_MONTH
            ),
            (beneficiaryClaim / 2) + (beneficiaryClaim / 48),
            "Vested one year and one month"
        );
        assertEq(
            wallet.vestedAmount(
                address(token), startTimestamp + SECONDS_PER_YEAR + SECONDS_PER_MONTH + 1
            ),
            (beneficiaryClaim / 2) + (beneficiaryClaim / 48),
            "Vested one year and one month plus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + (SECONDS_PER_YEAR * 3) - 1),
            ((beneficiaryClaim * 47) / 48),
            "Three years minus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + (SECONDS_PER_YEAR * 3)),
            (beneficiaryClaim),
            "Three years"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + (SECONDS_PER_YEAR * 3) + 1),
            (beneficiaryClaim),
            "Three years plus one"
        );
        assertEq(
            wallet.vestedAmount(address(token), startTimestamp + (SECONDS_PER_YEAR * 10)),
            (beneficiaryClaim),
            "Way into the future"
        );
    }

    function testReleaseAffordance() external {
        (ArbitrumVestingWallet wallet, L2ArbitrumToken token,,) = deployAndClaim();
        vm.prank(someRando);
        vm.expectRevert("ArbitrumVestingWallet: not beneficiary");
        wallet.release(address(token));
    }
}
