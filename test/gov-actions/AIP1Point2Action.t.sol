// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../src/gov-action-contracts/AIPs/AIP1Point2Action.sol" as a;
import "../util/ActionTestBase.sol";

contract AIP1Point2ActionTest is Test, ActionTestBase {
    function testAction() public {
        a.AIP1Point2Action action = new a.AIP1Point2Action(arbOneAddressRegistry);
        bytes memory callData = abi.encodeWithSelector(a.AIP1Point2Action.perform.selector);
        vm.prank(executor2);
        arbOneUe.execute(address(action), callData);

        assertEq(
            action.newConstitutionHash(),
            arbitrumDAOConstitution.constitutionHash(),
            "constitution hash not set"
        );
        assertEq(
            action.newProposalThreshold(),
            coreGov.proposalThreshold(),
            "core giv proposal threshold not set"
        );
        assertEq(
            action.newProposalThreshold(),
            treasuryGov.proposalThreshold(),
            "treasury gov proposal threshold not set"
        );
    }
}
