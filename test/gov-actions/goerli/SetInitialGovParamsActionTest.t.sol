// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../../src/gov-action-contracts/goerli/ArbGoerliSetInitialGovParamsAction.sol" as l2;
import "../../../src/gov-action-contracts/goerli/L1SetInitialGovParamsAction.sol" as l1;

import "../../util/ActionTestBase.sol";

contract SetInitialGovParamsActionTest is Test, ActionTestBase {
    function testL2() public {
        l2.ArbGoerliSetInitialGovParamsAction reinitAction =
            new l2.ArbGoerliSetInitialGovParamsAction(arbOneAddressRegistry);
        bytes memory callData =
            abi.encodeWithSelector(l2.ArbGoerliSetInitialGovParamsAction.perform.selector);
        vm.prank(executor2);
        arbOneUe.execute(address(reinitAction), callData);
    }

    function testL1() public {
        l1.L1SetInitialGovParamsAction reinitAction =
            new l1.L1SetInitialGovParamsAction(addressRegistry);
        bytes memory callData =
            abi.encodeWithSelector(l1.L1SetInitialGovParamsAction.perform.selector);
        vm.prank(executor0);
        ue.execute(address(reinitAction), callData);
    }
}
