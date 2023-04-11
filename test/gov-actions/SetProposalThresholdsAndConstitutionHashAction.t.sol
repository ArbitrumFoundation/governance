// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import
    "../../src/gov-action-contracts/governance/SetProposalThresholdsAndConstitutionHashAction.sol"
    as a;
import "../util/ActionTestBase.sol";

contract SetProposalThresholdsAndConstitutionHashActionTest is Test, ActionTestBase {
    function testAction() public {
        a.SetProposalThresholdsAndConstitutionHashAction action =
            new a.SetProposalThresholdsAndConstitutionHashAction(arbOneAddressRegistry);
        bytes memory callData = abi.encodeWithSelector(
            a.SetProposalThresholdsAndConstitutionHashAction.perform.selector
        );
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
