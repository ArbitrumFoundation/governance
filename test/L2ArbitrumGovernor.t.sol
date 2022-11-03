// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/L2ArbitrumGovernor.sol";
import "../src/ArbitrumTimelock.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "forge-std/Test.sol";

contract L2GovernanceFactoryTest is Test {
    address l1TokenAddress = address(1);
    uint256 initialTokenSupply = 10000;
    address tokenOwner = address(2);
    uint256 votingPeriod = 6;
    uint256 votingDelay = 9;
    address excludeListMember = address(3);
    uint256 quorumNumerator = 3;

    address[] stubAddressArray = [address(6)];
    address someRando = address(7);

    function deployAndInit()
        private
        returns (
            L2ArbitrumGovernor l2ArbitrumGovernor,
            L2ArbitrumToken token,
            ArbitrumTimelock timelock
        )
    {
        address tokenLogic = address(new L2ArbitrumToken());
        TransparentUpgradeableProxy tokenProxy = new TransparentUpgradeableProxy(
                tokenLogic,
                address(new ProxyAdmin()),
                bytes("")
            );
        L2ArbitrumToken token = L2ArbitrumToken((address(tokenProxy)));
        token.initialize(l1TokenAddress, initialTokenSupply, tokenOwner);

        address _l2TimelockLogic = address(new ArbitrumTimelock());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _l2TimelockLogic,
            address(new ProxyAdmin()),
            bytes("")
        );
        timelock = ArbitrumTimelock(payable(address(proxy)));
        timelock.initialize(1, stubAddressArray, stubAddressArray);

        address l2ArbitrumGovernorLogic = address(new L2ArbitrumGovernor());
        TransparentUpgradeableProxy govProxy = new TransparentUpgradeableProxy(
            l2ArbitrumGovernorLogic,
            address(new ProxyAdmin()),
            bytes("")
        );
        L2ArbitrumGovernor l2ArbitrumGovernor = L2ArbitrumGovernor(
            payable(address(govProxy))
        );
        l2ArbitrumGovernor.initialize(
            token,
            timelock,
            votingPeriod,
            votingDelay
        );
        return (l2ArbitrumGovernor, token, timelock);
    }

    function testCantReinit() external {
        (
            L2ArbitrumGovernor l2ArbitrumGovernor,
            L2ArbitrumToken token,
            ArbitrumTimelock timelock
        ) = deployAndInit();

        vm.expectRevert("Initializable: contract is already initialized");
        l2ArbitrumGovernor.initialize(
            token,
            timelock,
            votingPeriod,
            votingDelay
        );
    }

    function testProperlyInitialized() external {
        (
            L2ArbitrumGovernor l2ArbitrumGovernor,
            L2ArbitrumToken token,
            ArbitrumTimelock timelock
        ) = deployAndInit();
        assertEq(
            l2ArbitrumGovernor.votingDelay(),
            votingDelay,
            "votingDelay not set properly"
        );
        assertEq(
            l2ArbitrumGovernor.votingPeriod(),
            votingPeriod,
            "votingPeriod not set properly"
        );
    }

    function testPastCirculatingSupply() external {
        (
            L2ArbitrumGovernor l2ArbitrumGovernor,
            L2ArbitrumToken token,
            ArbitrumTimelock timelock
        ) = deployAndInit();
        address circulatingVotesExcludeDummyAddress = l2ArbitrumGovernor
            .circulatingVotesExcludeDummyAddress();

        vm.warp(200000000000000000);
        vm.roll(2);
        assertEq(
            l2ArbitrumGovernor.getPastCirculatingSupply(1),
            10000,
            "Inital supply error"
        );

        vm.prank(tokenOwner);
        token.mint(someRando, 200);
        vm.roll(3);
        assertEq(
            l2ArbitrumGovernor.getPastCirculatingSupply(2),
            10200,
            "Mint should be reflected in getPastCirculatingSupply"
        );
        assertEq(
            l2ArbitrumGovernor.quorum(2),
            10200 * quorumNumerator / 100,
            "Mint should be reflected in quorum"
        );
        vm.warp(300000000000000000);
        vm.prank(tokenOwner);
        token.mint(excludeListMember, 200);

        vm.prank(excludeListMember);
        token.delegate(circulatingVotesExcludeDummyAddress);
        vm.roll(4);
        assertEq(
            token.getPastVotes(circulatingVotesExcludeDummyAddress, 3),
            200,
            "didn't delegate to votes circulatingVotesExcludeDummyAddress"
        );

        assertEq(
            l2ArbitrumGovernor.getPastCirculatingSupply(3),
            10200,
            "votes at exlcude-address member shouldn't affect circulating supply"
        );
        assertEq(
            l2ArbitrumGovernor.quorum(3),
            10200 * quorumNumerator / 100,
            "votes at exlcude-address member shouldn't affect quorum"
        );
    }
}
