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
    address excludeListMember1 = address(3);
    address excludeListMember2 = address(4);
    address[] excludeList = [excludeListMember1, excludeListMember2];
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
            votingDelay,
            excludeList
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
            votingDelay,
            excludeList
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
        assertTrue(
            l2ArbitrumGovernor.circulatingVotesExcludeMap(excludeListMember1),
            "excludeListMember1 not excluded"
        );
        assertTrue(
            l2ArbitrumGovernor.circulatingVotesExcludeMap(excludeListMember2),
            "excludeListMember2 not excluded"
        );
        assertFalse(
            l2ArbitrumGovernor.circulatingVotesExcludeMap(someRando),
            "Excluded some rando"
        );

        assertEq(
            l2ArbitrumGovernor.circulatingVotesExcludeList(0),
            excludeListMember1,
            ""
        );
        assertEq(
            l2ArbitrumGovernor.circulatingVotesExcludeList(1),
            excludeListMember2,
            ""
        );
        vm.expectRevert();
        assertEq(l2ArbitrumGovernor.circulatingVotesExcludeList(2), address(0));
    }

    function testPastCirculatingSupply() external {
        (
            L2ArbitrumGovernor l2ArbitrumGovernor,
            L2ArbitrumToken token,
            ArbitrumTimelock timelock
        ) = deployAndInit();
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
            "Mint not reflected in quorum"
        );
        // TODO DG: Get this passing
        vm.warp(300000000000000000);
        vm.prank(tokenOwner);
        token.mint(excludeListMember1, 200);
        vm.roll(4);
        assertEq(
            l2ArbitrumGovernor.getPastCirculatingSupply(3),
            10200,
            "minting to exlcude-list member shouldn't affect circulating supply"
        );
    }

    function testExcludedVote() external {
        (
            L2ArbitrumGovernor l2ArbitrumGovernor,
            L2ArbitrumToken token,
            ArbitrumTimelock timelock
        ) = deployAndInit();
        vm.prank(excludeListMember1);
        vm.expectRevert("CAN'T VOTE");
        l2ArbitrumGovernor.castVote(0, 0);
    }
}
