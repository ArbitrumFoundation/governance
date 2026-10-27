// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../src/gov-action-contracts/governance/SetSCThresholdAndUpdateConstitutionAction.sol";
import "../../src/gov-action-contracts/governance/ConstitutionActionLib.sol";
import "../util/ActionTestBase.sol";
import "../util/DeployGnosisWithModule.sol";

contract AIPIncreaseNonEmergencySCThresholdAction is
    Test,
    ActionTestBase,
    DeployGnosisWithModule
{
    uint256 oldThreshold = 1;
    uint256 newThreshold = 2;
    address[] owners = [address(123), address(456)];

    bytes32 constHash1 = bytes32("0x1");
    bytes32 constHash2 = bytes32("0x2");
    bytes32 constHash3 = bytes32("0x3");
    bytes32 constHash4 = bytes32("0x4");
    bytes32 constHash5 = bytes32("0x5");

    address safeAddress;
    // TODO: outdated tests
    // function runUpdate(
    //     bytes32 _initialConstitutionHash,
    //     bytes32 _oldConstitutionHash1,
    //     bytes32 _newConstitutionHash1,
    //     bytes32 _oldConstitutionHash2,
    //     bytes32 _newConstitutionHash2
    // ) public {
    //     safeAddress = deploySafe(owners, oldThreshold, address(arbOneUe));

    //     vm.prank(address(arbOneUe));
    //     arbitrumDAOConstitution.setConstitutionHash(_initialConstitutionHash);
    //     assertEq(
    //         arbitrumDAOConstitution.constitutionHash(),
    //         _initialConstitutionHash,
    //         "initial constitution hash set"
    //     );

    //     address action = address(
    //         new SetSCThresholdAndConditionallyUpdateConstitutionAction({
    //             _gnosisSafe: IGnosisSafe(safeAddress),
    //             _oldThreshold: oldThreshold,
    //             _newThreshold: newThreshold,
    //             _constitution: IArbitrumDAOConstitution(address(arbitrumDAOConstitution)),
    //             _oldConstitutionHash1: _oldConstitutionHash1,
    //             _newConstitutionHash1: _newConstitutionHash1,
    //             _oldConstitutionHash2: _oldConstitutionHash2,
    //             _newConstitutionHash2: _newConstitutionHash2
    //         })
    //     );

    //     vm.prank(executor2);
    //     arbOneUe.execute(
    //         action,
    //         abi.encodeWithSelector(
    //             SetSCThresholdAndConditionallyUpdateConstitutionAction.perform.selector
    //         )
    //     );
    // }

    // function testUpdateInitialHashIsOldHash1() public {
    //     runUpdate({
    //         _initialConstitutionHash: constHash1,
    //         _oldConstitutionHash1: constHash1,
    //         _newConstitutionHash1: constHash2,
    //         _oldConstitutionHash2: constHash3,
    //         _newConstitutionHash2: constHash4
    //     });
    //     assertEq(
    //         arbitrumDAOConstitution.constitutionHash(), constHash2, "proper constitution hash set"
    //     );
    //     assertEq(IGnosisSafe(safeAddress).getThreshold(), newThreshold, "new threshold set");
    // }

    // function testUpdateInitialHashIsOldHash2() public {
    //     runUpdate({
    //         _initialConstitutionHash: constHash3,
    //         _oldConstitutionHash1: constHash1,
    //         _newConstitutionHash1: constHash2,
    //         _oldConstitutionHash2: constHash3,
    //         _newConstitutionHash2: constHash4
    //     });
    //     assertEq(
    //         arbitrumDAOConstitution.constitutionHash(), constHash4, "proper constitution hash set"
    //     );
    //     assertEq(IGnosisSafe(safeAddress).getThreshold(), newThreshold, "new threshold set");
    // }

    // function testUnfoundConstitutionHash() public {
    //     safeAddress = deploySafe(owners, oldThreshold, address(arbOneUe));
    //     vm.prank(address(arbOneUe));
    //     arbitrumDAOConstitution.setConstitutionHash(constHash1);
    //     assertEq(
    //         arbitrumDAOConstitution.constitutionHash(), constHash1, "initial constitution hash set"
    //     );
    //     address action = address(
    //         new SetSCThresholdAndConditionallyUpdateConstitutionAction({
    //             _gnosisSafe: IGnosisSafe(safeAddress),
    //             _oldThreshold: oldThreshold,
    //             _newThreshold: newThreshold,
    //             _constitution: IArbitrumDAOConstitution(address(arbitrumDAOConstitution)),
    //             _oldConstitutionHash1: constHash2,
    //             _newConstitutionHash1: constHash3,
    //             _oldConstitutionHash2: constHash4,
    //             _newConstitutionHash2: constHash5
    //         })
    //     );
    //     vm.expectRevert(
    //         abi.encodeWithSelector(ConstitutionActionLib.UnhandledConstitutionHash.selector)
    //     );
    //     vm.prank(executor2);
    //     arbOneUe.execute(
    //         action,
    //         abi.encodeWithSelector(
    //             SetSCThresholdAndConditionallyUpdateConstitutionAction.perform.selector
    //         )
    //     );
    // }
}
