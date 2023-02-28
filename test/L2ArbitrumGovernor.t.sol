// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/L2ArbitrumGovernor.sol";
import "../src/ArbitrumTimelock.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import "../src/L2ArbitrumToken.sol";
import "./util/TestUtil.sol";

import "forge-std/Test.sol";

contract L2ArbitrumGovernorTest is Test {
    address l1TokenAddress = address(137);
    uint256 initialTokenSupply = 50_000;
    address tokenOwner = address(238);
    uint256 votingPeriod = 6;
    uint256 votingDelay = 9;
    address excludeListMember = address(339);
    uint256 quorumNumerator = 500;
    uint256 proposalThreshold = 1;
    uint64 initialVoteExtension = 5;

    address[] stubAddressArray = [address(640)];
    address someRando = address(741);
    address executor = address(842);

    function deployAndInit()
        private
        returns (L2ArbitrumGovernor, L2ArbitrumToken, ArbitrumTimelock)
    {
        L2ArbitrumToken token =
            L2ArbitrumToken(TestUtil.deployProxy(address(new L2ArbitrumToken())));
        token.initialize(l1TokenAddress, initialTokenSupply, tokenOwner);

        ArbitrumTimelock timelock =
            ArbitrumTimelock(payable(TestUtil.deployProxy(address(new ArbitrumTimelock()))));
        timelock.initialize(1, stubAddressArray, stubAddressArray);

        L2ArbitrumGovernor l2ArbitrumGovernor =
            L2ArbitrumGovernor(payable(TestUtil.deployProxy(address(new L2ArbitrumGovernor()))));
        l2ArbitrumGovernor.initialize(
            token,
            timelock,
            executor,
            votingDelay,
            votingPeriod,
            quorumNumerator,
            proposalThreshold,
            initialVoteExtension
        );
        return (l2ArbitrumGovernor, token, timelock);
    }

    function testCantReinit() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor, L2ArbitrumToken token, ArbitrumTimelock timelock) =
            deployAndInit();

        vm.expectRevert("Initializable: contract is already initialized");
        l2ArbitrumGovernor.initialize(
            token,
            timelock,
            someRando,
            votingDelay,
            votingPeriod,
            quorumNumerator,
            proposalThreshold,
            initialVoteExtension
        );
    }

    function testProperlyInitialized() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor,,) = deployAndInit();
        assertEq(l2ArbitrumGovernor.votingDelay(), votingDelay, "votingDelay not set properly");
        assertEq(l2ArbitrumGovernor.votingPeriod(), votingPeriod, "votingPeriod not set properly");
    }

    function testPastCirculatingSupplyMint() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor, L2ArbitrumToken token,) = deployAndInit();

        vm.warp(200_000_000_000_000_000);
        vm.roll(2);

        vm.prank(tokenOwner);
        token.mint(someRando, 200);
        vm.roll(3);
        assertEq(
            l2ArbitrumGovernor.getPastCirculatingSupply(2),
            initialTokenSupply + 200,
            "Mint should be reflected in getPastCirculatingSupply"
        );
        assertEq(
            l2ArbitrumGovernor.quorum(2),
            ((initialTokenSupply + 200) * quorumNumerator) / 10_000,
            "Mint should be reflected in quorum"
        );
    }

    function testPastCirculatingSupplyExclude() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor, L2ArbitrumToken token,) = deployAndInit();
        address excludeAddress = l2ArbitrumGovernor.EXCLUDE_ADDRESS();

        vm.roll(3);
        vm.warp(300_000_000_000_000_000);
        vm.prank(tokenOwner);
        token.mint(excludeListMember, 300);

        vm.prank(excludeListMember);
        token.delegate(excludeAddress);
        vm.roll(4);
        assertEq(
            token.getPastVotes(excludeAddress, 3), 300, "didn't delegate to votes exclude address"
        );

        assertEq(
            l2ArbitrumGovernor.getPastCirculatingSupply(3),
            initialTokenSupply,
            "votes at exlcude-address member shouldn't affect circulating supply"
        );
        assertEq(
            l2ArbitrumGovernor.quorum(3),
            (initialTokenSupply * quorumNumerator) / 10_000,
            "votes at exlcude-address member shouldn't affect quorum"
        );
    }

    function testPastCirculatingSupply() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor,,) = deployAndInit();

        vm.warp(200_000_000_000_000_000);
        vm.roll(2);
        assertEq(
            l2ArbitrumGovernor.getPastCirculatingSupply(1),
            initialTokenSupply,
            "Inital supply error"
        );
    }

    function testExecutorPermissions() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor,,) = deployAndInit();
        vm.startPrank(executor);

        l2ArbitrumGovernor.relay(
            address(l2ArbitrumGovernor),
            0,
            abi.encodeWithSelector(l2ArbitrumGovernor.setProposalThreshold.selector, 2)
        );
        assertEq(l2ArbitrumGovernor.proposalThreshold(), 2, "Prop threshold");

        l2ArbitrumGovernor.relay(
            address(l2ArbitrumGovernor),
            0,
            abi.encodeWithSelector(l2ArbitrumGovernor.setVotingDelay.selector, 2)
        );
        assertEq(l2ArbitrumGovernor.votingDelay(), 2, "Voting delay");

        l2ArbitrumGovernor.relay(
            address(l2ArbitrumGovernor),
            0,
            abi.encodeWithSelector(l2ArbitrumGovernor.setVotingPeriod.selector, 2)
        );
        assertEq(l2ArbitrumGovernor.votingPeriod(), 2, "Voting period");

        l2ArbitrumGovernor.relay(
            address(l2ArbitrumGovernor),
            0,
            abi.encodeWithSelector(l2ArbitrumGovernor.updateQuorumNumerator.selector, 400)
        );
        assertEq(l2ArbitrumGovernor.quorumNumerator(), 400, "Quorum num");

        l2ArbitrumGovernor.relay(
            address(l2ArbitrumGovernor),
            0,
            abi.encodeWithSelector(l2ArbitrumGovernor.updateTimelock.selector, address(137))
        );
        assertEq(l2ArbitrumGovernor.timelock(), address(137), "Timelock");

        vm.stopPrank();
    }

    function testExecutorPermissionsFail() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor,,) = deployAndInit();

        vm.startPrank(someRando);

        vm.expectRevert("Governor: onlyGovernance");
        l2ArbitrumGovernor.setProposalThreshold(2);

        vm.expectRevert("Governor: onlyGovernance");
        l2ArbitrumGovernor.setVotingDelay(2);

        vm.expectRevert("Governor: onlyGovernance");
        l2ArbitrumGovernor.setVotingPeriod(2);

        vm.expectRevert("Governor: onlyGovernance");
        l2ArbitrumGovernor.updateQuorumNumerator(400);

        vm.expectRevert("Governor: onlyGovernance");
        l2ArbitrumGovernor.updateTimelock(TimelockControllerUpgradeable(payable(address(137))));

        vm.expectRevert("Ownable: caller is not the owner");
        l2ArbitrumGovernor.relay(
            address(l2ArbitrumGovernor),
            0,
            abi.encodeWithSelector(l2ArbitrumGovernor.updateQuorumNumerator.selector, 400)
        );

        vm.stopPrank();
    }
}
