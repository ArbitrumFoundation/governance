// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../src/security-council-mgmt/SecurityCouncilManager.sol";
import "../../src/UpgradeExecRouterBuilder.sol";

import "../util/TestUtil.sol";
import "../util/MockArbSys.sol";

contract SecurityCouncilManagerTest is Test {
    address[] secondCohort = new address[](6);
    address[6] _secondCohort =
        [address(1111), address(1112), address(1113), address(1114), address(1114), address(1116)];

    address[] firstCohort = new address[](6);
    address[6] _firstCohort =
        [address(2221), address(2222), address(2223), address(2224), address(2224), address(2226)];

    address[] newCohort = new address[](6);
    address[6] _newCohort =
        [address(3331), address(3332), address(3333), address(3334), address(3334), address(3336)];

    SecurityCouncilManager scm;
    UpgradeExecRouterBuilder uerb;
    address[] memberRemovers = new address[](2);
    address memberRemover1 = address(4444);
    address memberRemover2 = address(4445);

    SecurityCouncilManagerRoles roles = SecurityCouncilManagerRoles({
        admin: address(4441),
        cohortUpdator: address(4442),
        memberAdder: address(4443),
        memberRemovers: memberRemovers,
        memberRotator: address(4446)
    });

    uint256 minDelay = uint256(5);

    address rando = address(6661);

    address memberToAdd = address(7771);

    address l1ArbitrumTimelock = address(8881);

    address payable l2CoreGovTimelock = payable(address(9991));

    uint256 l1TimelockMinDelay = uint256(1);
    ChainAndUpExecLocation[] chainAndUpExecLocation;
    SecurityCouncilData[] securityCouncils;

    function setUp() public {
        uerb = new UpgradeExecRouterBuilder({
            _upgradeExecutors:chainAndUpExecLocation,
            _l1ArbitrumTimelock: l1ArbitrumTimelock,
            _l1TimelockMinDelay: l1TimelockMinDelay
        });
        for (uint256 i = 0; i < 6; i++) {
            secondCohort[i] = _secondCohort[i];
            firstCohort[i] = _firstCohort[i];
        }
        address prox = TestUtil.deployProxy(address(new SecurityCouncilManager()));
        scm = SecurityCouncilManager(payable(prox));
        scm.initialize(firstCohort, secondCohort, securityCouncils, roles, l2CoreGovTimelock, uerb);

        bytes memory code = vm.getDeployedCode("MockArbSys.sol:ArbSysMock");
        address overrideAddress = address(0x0000000000000000000000000000000000000064);
        vm.etch(overrideAddress, code);
    }

    function testInitialization() public {
        vm.expectRevert("Initializable: contract is already initialized");
        scm.initialize(firstCohort, secondCohort, securityCouncils, roles, l2CoreGovTimelock, uerb);

        assertTrue(
            TestUtil.areAddressArraysEqual(firstCohort, scm.getFirstCohort()), "first cohort set"
        );
        assertTrue(
            TestUtil.areAddressArraysEqual(secondCohort, scm.getSecondCohort()), "second cohort set"
        );

        assertTrue(scm.hasRole(scm.DEFAULT_ADMIN_ROLE(), roles.admin), "admin role set");
        assertTrue(
            scm.hasRole(scm.ELECTION_EXECUTOR_ROLE(), roles.cohortUpdator),
            "election executor role set"
        );
        assertTrue(scm.hasRole(scm.MEMBER_ADDER_ROLE(), roles.memberAdder), "member adder role set");
        assertTrue(
            scm.hasRole(scm.MEMBER_REMOVER_ROLE(), roles.memberRemovers[0]),
            "member remover role set"
        );
        assertTrue(
            scm.hasRole(scm.MEMBER_REMOVER_ROLE(), roles.memberRemovers[1]),
            "member remover role set"
        );
        assertTrue(
            scm.hasRole(scm.MEMBER_ROTATOR_ROLE(), roles.memberRotator),
            "member memberRotator role set"
        );

        assertEq(l2CoreGovTimelock, scm.l2CoreGovTimelock(), "l2CoreGovTimelock set");

        assertEq(address(uerb), address(scm.router()), "exec router set");
    }

    //     function testRemoveMember() public {
    //         vm.prank(rando);
    //         vm.expectRevert();
    //         scm.removeMember(rando);

    //         vm.prank(roles.memberRemovers[0]);
    //         vm.expectRevert("SecurityCouncilManager: member not found");
    //         scm.removeMember(rando);

    //         removeFirstMember();
    //         address[] memory remainingMembers = new address[](5);
    //         for (uint256 i = 1; i < secondCohort.length; i++) {
    //             remainingMembers[i - 1] = secondCohort[i];
    //         }
    //         assertTrue(
    //             TestUtil.areAddressArraysEqual(remainingMembers, scm.getMarchCohort()),
    //             "member removed from march chohort"
    //         );
    //         address[] memory membersToRemove = new address[](1);
    //         membersToRemove[0] = secondCohort[0];

    //         address[] memory membersToAdd = new address[](0);
    //         checkOperationScheduledAndExecute(membersToAdd, membersToRemove);
    //     }

    //     function testAddMember() public {
    //         vm.prank(rando);
    //         vm.expectRevert();
    //         scm.addMemberToCohort(memberToAdd, Cohort.MARCH);

    //         vm.prank(roles.memberAdder);
    //         vm.expectRevert("SecurityCouncilManager: cohort is full");
    //         scm.addMemberToCohort(memberToAdd, Cohort.MARCH);

    //         removeFirstMember();

    //         vm.startPrank(roles.memberAdder);

    //         vm.expectRevert("SecurityCouncilManager: member already in firstCohort cohort");
    //         scm.addMemberToCohort(firstCohort[0], Cohort.MARCH);

    //         scm.addMemberToCohort(memberToAdd, Cohort.MARCH);
    //         address[] memory newMarchCohort = new address[](6);
    //         for (uint256 i = 1; i < secondCohort.length; i++) {
    //             newMarchCohort[i - 1] = secondCohort[i];
    //         }
    //         newMarchCohort[5] = memberToAdd;

    //         assertTrue(
    //             TestUtil.areAddressArraysEqual(newMarchCohort, scm.getMarchCohort()),
    //             "member added to march chohort"
    //         );

    //         assertTrue(
    //             TestUtil.areAddressArraysEqual(firstCohort, scm.getSeptemberCohort()),
    //             "september cohort untouched"
    //         );

    //         address[] memory membersToRemove = new address[](0);
    //         address[] memory membersToAdd = new address[](1);
    //         membersToAdd[0] = memberToAdd;
    //         checkOperationScheduledAndExecute(membersToAdd, membersToRemove);
    //     }

    //     function testUpdateCohortAffordances() public {
    //         vm.prank(rando);
    //         vm.expectRevert();
    //         scm.executeElectionResult(newCohort, Cohort.MARCH);

    //         vm.startPrank(roles.cohortUpdator);
    //         address[] memory newSmallCohort = new address[](1);
    //         newSmallCohort[0] = rando;
    //         vm.expectRevert("SecurityCouncilManager: invalid cohort length");
    //         scm.executeElectionResult(newSmallCohort, Cohort.MARCH);

    //         vm.stopPrank();
    //     }

    //     function testUpdateMarchCohort() public {
    //         vm.startPrank(roles.cohortUpdator);
    //         scm.executeElectionResult(newCohort, Cohort.MARCH);
    //         assertTrue(
    //             TestUtil.areAddressArraysEqual(newCohort, scm.getMarchCohort()), "march cohort updated"
    //         );

    //         assertTrue(
    //             TestUtil.areAddressArraysEqual(firstCohort, scm.getSeptemberCohort()),
    //             "september cohort untouched"
    //         );
    //         checkOperationScheduledAndExecute(newCohort, secondCohort);
    //     }

    //     function testUpdateSeptemberCohort() public {
    //         vm.startPrank(roles.cohortUpdator);
    //         scm.executeElectionResult(newCohort, Cohort.SEPTEMBER);
    //         assertTrue(
    //             TestUtil.areAddressArraysEqual(newCohort, scm.getSeptemberCohort()),
    //             "september cohort updated"
    //         );
    //         assertTrue(
    //             TestUtil.areAddressArraysEqual(secondCohort, scm.getMarchCohort()),
    //             "march cohort untouched"
    //         );
    //         checkOperationScheduledAndExecute(newCohort, firstCohort);
    //     }

    //     // TODO: test rotator

    //     // helpers
    //     function checkOperationScheduledAndExecute(
    //         address[] memory membersToAdd,
    //         address[] memory membersToRemove
    //     ) internal {
    //         bytes memory payload = abi.encodeWithSelector(
    //             IL1SecurityCouncilUpdateRouter.scheduleUpdateMembers.selector,
    //             abi.encode(membersToAdd, membersToRemove)
    //         );
    //         bytes32 salt = scm.calculateUpdateSalt(scm.updateNonce() - 1, payload);
    //         bytes32 id = scm.hashOperation(address(scm), 0, payload, bytes32(0), salt);

    //         // check operation is scheduled
    //         assertTrue(scm.isOperationPending(id), "operation pending");
    //         assertFalse(scm.isOperationReady(id), "operation not ready");

    //         // warp so it can be executed
    //         vm.warp(block.timestamp + minDelay);
    //         assertTrue(scm.isOperationReady(id), "operation ready");

    //         vm.recordLogs();
    //         // execute
    //         scm.execute(address(scm), 0, payload, bytes32(0), salt);
    //         Vm.Log[] memory entries = vm.getRecordedLogs();

    //         // check ArbSysL2ToL1Tx event was emitted with payload
    //         assertEq(
    //             entries[0].topics[0],
    //             keccak256("ArbSysL2ToL1Tx(address,address,uint256,bytes)"),
    //             "ArbSysL2ToL1Tx emitted"
    //         );
    //         bytes32 payloadFromEventLog = entries[0].topics[1];
    //         assertEq(payloadFromEventLog, keccak256(payload), "eq");
    //     }

    //     function removeFirstMember() internal {
    //         address memberToRemove = secondCohort[0];
    //         vm.prank(roles.memberRemovers[0]);
    //         scm.removeMember(memberToRemove);
    //     }
}
