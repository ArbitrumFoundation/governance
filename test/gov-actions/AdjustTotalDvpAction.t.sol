// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {L2ArbitrumToken} from "../../src/L2ArbitrumToken.sol";

// forge test --fork-url $ARB_URL --fork-block-number 457010837 test/gov-actions/AdjustTotalDvpAction.t.sol -vvvv
contract AdjustTotalDvpActionTest is Test {
    L2ArbitrumToken constant token = L2ArbitrumToken(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address constant L1_TIMELOCK_ALIAS = 0xf7951D92B0C345144506576eC13Ecf5103aC905a;
    IUpgradeExecutor constant upgradeExecutor =
        IUpgradeExecutor(0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827);

    int256 constant ADJUSTMENT = -51165859783310262738992786;

    function testAdjustTotalDvp() external {
        if (!isFork()) {
            return;
        }

        assertEq(block.chainid, 42_161);

        uint256 totalDelegationBefore = token.getTotalDelegation();
        assertEq(
            totalDelegationBefore,
            5_458_617_008_862_503_155_958_282_897,
            "unexpected total delegation before adjustment"
        );

        vm.prank(L1_TIMELOCK_ALIAS);
        upgradeExecutor.executeCall(
            address(token),
            hex"ec20b526ffffffffffffffffffffffffffffffffffffffffffd5ad352eec3ec51bda416e"
        );

        uint256 totalDelegationAfter = token.getTotalDelegation();
        assertEq(
            totalDelegationAfter,
            5_407_451_149_079_192_893_219_290_111,
            "total delegation not adjusted correctly"
        );
        assertEq(
            int256(totalDelegationAfter) - int256(totalDelegationBefore),
            ADJUSTMENT,
            "adjustment mismatch"
        );
    }

    function isFork() internal view override returns (bool) {
        return address(token).code.length > 0;
    }
}

interface IUpgradeExecutor {
    function execute(address upgrade, bytes memory upgradeCallData) external payable;
    function executeCall(address target, bytes memory targetCallData) external payable;
}
