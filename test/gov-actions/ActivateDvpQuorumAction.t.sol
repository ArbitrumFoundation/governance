// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {ActivateDvpQuorumAction} from
    "../../src/gov-action-contracts/AIPs/ActivateDvpQuorumAction.sol";
import {L2ArbitrumGovernor} from "../../src/L2ArbitrumGovernor.sol";
import {L2ArbitrumToken} from "../../src/L2ArbitrumToken.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// forge test --fork-url $ARB_URL --fork-block-number 389149842 test/gov-actions/ActivateDvpQuorumAction.t.sol -vvvv
contract ActivateDvpQuorumActionTest is Test {
    function testAction() external {
        if (!isFork()) {
            return;
        }

        // ensure we are on a fork of arb1 before the upgrade
        assertEq(block.chainid, 42_161);
        assertEq(block.number, 23_569_916); // L1 block number corresponding to L2 block 389149842

        L2ArbitrumGovernor coreGovernor =
            L2ArbitrumGovernor(payable(0xf07DeD9dC292157749B6Fd268E37DF6EA38395B9));
        L2ArbitrumGovernor treasuryGovernor =
            L2ArbitrumGovernor(payable(0x789fC99093B09aD01C34DC7251D0C89ce743e5a4));

        uint256 prevCoreQuorum = coreGovernor.quorum(23_569_915);
        uint256 prevTreasuryQuorum = treasuryGovernor.quorum(23_569_915);
        assertEq(
            prevCoreQuorum,
            212_581_618_392_648_117_373_902_586,
            "unexpected core quorum before upgrade"
        );
        assertEq(
            prevTreasuryQuorum,
            141_721_078_928_432_078_249_268_390,
            "unexpected treasury quorum before upgrade"
        );

        address governorImpl = address(new L2ArbitrumGovernor());
        address tokenImpl = address(new L2ArbitrumToken());
        uint256 initialTDE = 5_275_963_013_349_154_829_183_295_064 + 200_000_000 ether; // excluded + 200M

        ActivateDvpQuorumAction action = new ActivateDvpQuorumAction({
            _l2AddressRegistry: 0x56C4E9Eb6c63aCDD19AeC2b1a00e4f0d7aBda9d3,
            _arbTokenProxy: 0x912CE59144191C1204E64559FE8253a0e49E6548,
            _govProxyAdmin: ProxyAdmin(0xdb216562328215E010F819B5aBe947bad4ca961e),
            _newGovernorImpl: governorImpl,
            _newTokenImpl: tokenImpl,
            _newCoreQuorumNumerator: 5000, // 50%
            _coreMinimumQuorum: 250 ether,
            _coreMaximumQuorum: 250_000_000 ether,
            _newTreasuryQuorumNumerator: 4000, // 40%
            _treasuryMinimumQuorum: 240 ether,
            _treasuryMaximumQuorum: 240_000_000 ether,
            _initialTotalDelegationEstimate: initialTDE
        });

        // make sure all the immutables are set properly
        assertEq(action.l2AddressRegistry(), 0x56C4E9Eb6c63aCDD19AeC2b1a00e4f0d7aBda9d3);
        assertEq(action.arbTokenProxy(), 0x912CE59144191C1204E64559FE8253a0e49E6548);
        assertEq(address(action.govProxyAdmin()), 0xdb216562328215E010F819B5aBe947bad4ca961e);
        assertEq(action.newGovernorImpl(), governorImpl);
        assertEq(action.newTokenImpl(), tokenImpl);
        assertEq(action.newCoreQuorumNumerator(), 5000);
        assertEq(action.coreMinimumQuorum(), 250 ether);
        assertEq(action.coreMaximumQuorum(), 250_000_000 ether);
        assertEq(action.newTreasuryQuorumNumerator(), 4000);
        assertEq(action.treasuryMinimumQuorum(), 240 ether);
        assertEq(action.treasuryMaximumQuorum(), 240_000_000 ether);
        assertEq(action.initialTotalDelegationEstimate(), initialTDE);

        // execute the action
        vm.prank(0xf7951D92B0C345144506576eC13Ecf5103aC905a); // L1 Timelock Alias
        IUpgradeExecutor(0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827).execute(
            address(action), abi.encodeCall(ActivateDvpQuorumAction.perform, ())
        );

        // verify the token was upgraded and initialized by checking the initial total delegation estimate
        L2ArbitrumToken token = L2ArbitrumToken(0x912CE59144191C1204E64559FE8253a0e49E6548);
        assertEq(
            token.getTotalDelegation(),
            initialTDE,
            "initial total delegation estimate not set correctly"
        );

        // verify the governors were upgraded by checking minimum and maximum quorum values
        assertEq(
            coreGovernor.minimumQuorum(),
            250 ether,
            "core governor minimum quorum not set correctly"
        );
        assertEq(
            coreGovernor.maximumQuorum(),
            250_000_000 ether,
            "core governor maximum quorum not set correctly"
        );
        assertEq(
            treasuryGovernor.minimumQuorum(),
            240 ether,
            "treasury governor minimum quorum not set correctly"
        );
        assertEq(
            treasuryGovernor.maximumQuorum(),
            240_000_000 ether,
            "treasury governor maximum quorum not set correctly"
        );

        // ensure that quorum is unchanged at previous block
        assertEq(
            coreGovernor.quorum(23_569_915),
            prevCoreQuorum,
            "core governor quorum changed at previous block"
        );
        assertEq(
            treasuryGovernor.quorum(23_569_915),
            prevTreasuryQuorum,
            "treasury governor quorum changed at previous block"
        );

        // ensure quorum is being calculated correctly at next block
        vm.roll(23_569_917);
        uint256 expectedCoreQuorum = (5000 * 200_000_000 ether) / 10_000;
        uint256 expectedTreasuryQuorum = (4000 * 200_000_000 ether) / 10_000;
        assertEq(
            coreGovernor.quorum(23_569_916),
            expectedCoreQuorum,
            "core governor quorum not calculated correctly at next block"
        );
        assertEq(
            treasuryGovernor.quorum(23_569_916),
            expectedTreasuryQuorum,
            "treasury governor quorum not calculated correctly at next block"
        );
    }
}

interface IUpgradeExecutor {
    function execute(address upgrade, bytes memory upgradeCallData) external payable;
}
