// TODO
// // SPDX-License-Identifier: Apache-2.0

// pragma solidity 0.8.16;

// import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
// import "../util/TestUtil.sol";
// import "../util/DeployGnosisWithModule.sol";
// import "../../src/security-council-mgmt/SecurityCouncilUpgradeExecutor.sol";
// import "../../src/security-council-mgmt/interfaces/IGnosisSafe.sol";

// import "forge-std/Test.sol";

// contract SecurityCouncilUpgradeExecutorTest is Test, DeployGnosisWithModule {
//     address updator = address(1112);
//     address admin = address(1113);
//     GnosisSafeL2 securityCouncil;
//     SecurityCouncilUpgradeExecutor scue;
//     address signer1 = address(1114);
//     address signer2 = address(1115);
//     address signer3 = address(1116);

//     address newSigner1 = address(1117);
//     address rando = address(1118);

//     function setUp() public {
//         address scueLogic = address(new SecurityCouncilUpgradeExecutor());
//         SecurityCouncilUpgradeExecutor _scue =
//             SecurityCouncilUpgradeExecutor(TestUtil.deployProxy(scueLogic));
//         address[] memory signers = new address[](3);
//         signers[0] = signer1;
//         signers[1] = signer2;
//         signers[2] = signer3;

//         uint256 threshold = 1;
//         address payable safeAddress = payable(deploySafe(signers, threshold, address(_scue)));
//         GnosisSafeL2 safe = GnosisSafeL2(safeAddress);
//         _scue.initialize(IGnosisSafe(address(safe)), updator, admin);

//         securityCouncil = safe;
//         scue = _scue;
//     }

//     function testAddOne() public {
//         address[] memory membersToAdd = new address[](1);
//         membersToAdd[0] = newSigner1;
//         address[] memory membersToRemove = new address[](0);

//         vm.prank(updator);
//         scue.updateMembers(membersToAdd, membersToRemove);

//         address[] memory owners = securityCouncil.getOwners();
//         address[] memory expectedOwners = new address[](4);
//         expectedOwners[0] = signer1;
//         expectedOwners[1] = signer2;
//         expectedOwners[2] = signer3;
//         expectedOwners[3] = newSigner1;

//         assertTrue(TestUtil.areAddressArraysEqual(owners, expectedOwners), "member added");
//     }

//     function testRemoveOne() public {
//         address[] memory membersToAdd = new address[](0);
//         address[] memory membersToRemove = new address[](1);
//         membersToRemove[0] = signer3;

//         vm.prank(updator);
//         scue.updateMembers(membersToAdd, membersToRemove);

//         address[] memory owners = securityCouncil.getOwners();
//         address[] memory expectedOwners = new address[](2);
//         expectedOwners[0] = signer1;
//         expectedOwners[1] = signer2;

//         assertTrue(TestUtil.areAddressArraysEqual(owners, expectedOwners), "member removed");
//     }

//     function testRemoveTwo() public {
//         address[] memory membersToAdd = new address[](0);
//         address[] memory membersToRemove = new address[](2);
//         membersToRemove[0] = signer2;
//         membersToRemove[1] = signer3;

//         vm.prank(updator);
//         scue.updateMembers(membersToAdd, membersToRemove);

//         address[] memory owners = securityCouncil.getOwners();
//         address[] memory expectedOwners = new address[](1);
//         expectedOwners[0] = signer1;

//         assertTrue(TestUtil.areAddressArraysEqual(owners, expectedOwners), "members removed");
//     }

//     function testAddOneRemoveOne() public {
//         address[] memory membersToAdd = new address[](1);
//         membersToAdd[0] = newSigner1;

//         address[] memory membersToRemove = new address[](1);
//         membersToRemove[0] = signer3;

//         vm.prank(updator);
//         scue.updateMembers(membersToAdd, membersToRemove);

//         address[] memory owners = securityCouncil.getOwners();
//         address[] memory expectedOwners = new address[](3);
//         expectedOwners[0] = signer1;
//         expectedOwners[1] = signer2;
//         expectedOwners[2] = newSigner1;
//         assertTrue(
//             TestUtil.areAddressArraysEqual(owners, expectedOwners), "members added and removed"
//         );
//     }

//     function testNoopAddRemove() public {
//         address[] memory membersToAdd = new address[](1);
//         // "add" a signer whose already a signer
//         membersToAdd[0] = signer1;

//         address[] memory membersToRemove = new address[](1);
//         // "remove" a signer that isn't a signer
//         membersToRemove[0] = newSigner1;

//         vm.prank(updator);
//         scue.updateMembers(membersToAdd, membersToRemove);

//         address[] memory owners = securityCouncil.getOwners();
//         address[] memory expectedOwners = new address[](3);
//         expectedOwners[0] = signer1;
//         expectedOwners[1] = signer2;
//         expectedOwners[2] = signer3;
//         assertTrue(TestUtil.areAddressArraysEqual(owners, expectedOwners), "members unchanged");
//     }

//     function testAddAndRemoveCurrentMember() public {
//         address[] memory membersToAdd = new address[](1);
//         // "add" a signer whose already a signer
//         membersToAdd[0] = signer1;

//         address[] memory membersToRemove = new address[](1);
//         // "remove" the same signer
//         membersToRemove[0] = signer1;

//         vm.prank(updator);
//         scue.updateMembers(membersToAdd, membersToRemove);

//         address[] memory owners = securityCouncil.getOwners();
//         address[] memory expectedOwners = new address[](3);
//         expectedOwners[0] = signer1;
//         expectedOwners[1] = signer2;
//         expectedOwners[2] = signer3;
//         assertTrue(TestUtil.areAddressArraysEqual(owners, expectedOwners), "members unchanged");
//     }

//     function testOnlyUpdatorCanRemove() public {
//         address[] memory membersToAdd = new address[](0);
//         address[] memory membersToRemove = new address[](0);

//         vm.prank(rando);
//         vm.expectRevert();
//         scue.updateMembers(membersToAdd, membersToRemove);
//     }
// }
