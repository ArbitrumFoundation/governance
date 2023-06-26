// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../src/security-council-mgmt/SecurityCouncilManager.sol";
import "../../src/security-council-mgmt/interfaces/IL1SecurityCouncilUpdateRouter.sol";
import "../util/TestUtil.sol";
import "../util/MockArbSys.sol";

contract SecurityCouncilManagerTest is Test {
    address[] marchCohort = new address[](6);
    address[6] _marchCohort =
        [address(1111), address(1112), address(1113), address(1114), address(1114), address(1116)];

    address[] septemberCohort = new address[](6);
    address[6] _septemberCohort =
        [address(2221), address(2222), address(2223), address(2224), address(2224), address(2226)];

    address[] newCohort = new address[](6);
    address[6] _newCohort =
        [address(3331), address(3332), address(3333), address(3334), address(3334), address(3336)];

    SecurityCouncilManager scm;

    address[] memberRemovers = new address[](2);
    address memberRemover1 = address(4444);
    address memberRemover2 = address(4445);

    Roles roles = Roles({
        admin: address(4441),
        cohortUpdator: address(4442),
        memberAdder: address(4443),
        memberRemovers: memberRemovers,
        memberRotator: address(4446)
    });

    address l1SecurityCouncilUpdateRouter = address(5551);
    uint256 minDelay = uint256(5);

    address rando = address(6661);

    address memberToAdd = address(7771);

    function setUp() public {
        for (uint256 i = 0; i < 6; i++) {
            marchCohort[i] = _marchCohort[i];
            septemberCohort[i] = _septemberCohort[i];
        }
        address prox = TestUtil.deployProxy(address(new SecurityCouncilManager()));
        scm = SecurityCouncilManager(payable(prox));
        scm.initialize(marchCohort, septemberCohort, roles, l1SecurityCouncilUpdateRouter, minDelay);

        bytes memory code = vm.getDeployedCode("MockArbSys.sol:ArbSysMock");
        address overrideAddress = address(0x0000000000000000000000000000000000000064);
        vm.etch(overrideAddress, code);
    }

    function testInitialization() public {
        vm.expectRevert("Initializable: contract is already initialized");
        scm.initialize(marchCohort, septemberCohort, roles, l1SecurityCouncilUpdateRouter, minDelay);

        assertTrue(
            TestUtil.areAddressArraysEqual(marchCohort, scm.getMarchCohort()), "march cohort set"
        );
        assertTrue(
            TestUtil.areAddressArraysEqual(septemberCohort, scm.getSeptemberCohort()),
            "september cohort set"
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
            "memver memberRotator role set"
        );

        assertEq(
            l1SecurityCouncilUpdateRouter,
            scm.l1SecurityCouncilUpdateRouter(),
            "l1SecurityCouncilUpdateRouter set"
        );
        assertEq(minDelay, scm.getMinDelay(), "min delay set");
    }

    function testRemoveMember() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.removeMember(rando);

        vm.prank(roles.memberRemovers[0]);
        vm.expectRevert("SecurityCouncilManager: member not found");
        scm.removeMember(rando);

        // vm.recordLogs();

        removeFirstMember();
        address[] memory remainingMembers = new address[](5);
        for (uint256 i = 1; i < marchCohort.length; i++) {
            remainingMembers[i - 1] = marchCohort[i];
        }
        assertTrue(
            TestUtil.areAddressArraysEqual(remainingMembers, scm.getMarchCohort()),
            "member removed from march chohort"
        );

        // Vm.Log[] memory entries = vm.getRecordedLogs();
        // assertEq(
        //     entries[0].topics[0],
        //     keccak256("CallScheduled(bytes32,uint256,address,uint256,bytes,bytes32,uint256)"),
        //     "CallScheduled emitted"
        // );
        // bytes32 id = entries[0].topics[1];
        address[] memory membersToRemove = new address[](1);
        membersToRemove[0] = marchCohort[0];

        address[] memory membersToAdd = new address[](0);
        checkOperationScheduledAndExecute(membersToAdd, membersToRemove);
    }

    function testAddMember() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.addMemberToCohort(memberToAdd, Cohort.MARCH);

        vm.prank(roles.memberAdder);
        vm.expectRevert("SecurityCouncilManager: cohort is full");
        scm.addMemberToCohort(memberToAdd, Cohort.MARCH);

        removeFirstMember();

        vm.startPrank(roles.memberAdder);

        vm.expectRevert("SecurityCouncilManager: member already in septemberCohort cohort");
        scm.addMemberToCohort(septemberCohort[0], Cohort.MARCH);

        scm.addMemberToCohort(memberToAdd, Cohort.MARCH);
        address[] memory newMarchCohort = new address[](6);
        for (uint256 i = 1; i < marchCohort.length; i++) {
            newMarchCohort[i - 1] = marchCohort[i];
        }
        newMarchCohort[5] = memberToAdd;

        assertTrue(
            TestUtil.areAddressArraysEqual(newMarchCohort, scm.getMarchCohort()),
            "member added to march chohort"
        );

        assertTrue(
            TestUtil.areAddressArraysEqual(septemberCohort, scm.getSeptemberCohort()),
            "september cohort untouched"
        );

        address[] memory membersToRemove = new address[](0);
        address[] memory membersToAdd = new address[](1);
        membersToAdd[0] = memberToAdd;
        checkOperationScheduledAndExecute(membersToAdd, membersToRemove);
    }

    function testUpdateCohortAffordances() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.executeElectionResult(newCohort, Cohort.MARCH);

        vm.startPrank(roles.cohortUpdator);
        address[] memory newSmallCohort = new address[](1);
        newSmallCohort[0] = rando;
        vm.expectRevert("SecurityCouncilManager: invalid cohort length");
        scm.executeElectionResult(newSmallCohort, Cohort.MARCH);

        vm.stopPrank();
    }

    function testUpdateMarchCohort() public {
        vm.startPrank(roles.cohortUpdator);
        scm.executeElectionResult(newCohort, Cohort.MARCH);
        assertTrue(
            TestUtil.areAddressArraysEqual(newCohort, scm.getMarchCohort()), "march cohort updated"
        );

        assertTrue(
            TestUtil.areAddressArraysEqual(septemberCohort, scm.getSeptemberCohort()),
            "september cohort untouched"
        );
        checkOperationScheduledAndExecute(newCohort, marchCohort);
    }

    function testUpdateSeptemberCohort() public {
        vm.startPrank(roles.cohortUpdator);
        scm.executeElectionResult(newCohort, Cohort.SEPTEMBER);
        assertTrue(
            TestUtil.areAddressArraysEqual(newCohort, scm.getSeptemberCohort()),
            "september cohort updated"
        );
        assertTrue(
            TestUtil.areAddressArraysEqual(marchCohort, scm.getMarchCohort()),
            "march cohort untouched"
        );
        checkOperationScheduledAndExecute(newCohort, septemberCohort);
    }

    // TODO: test rotator

    // helpers
    function checkOperationScheduledAndExecute(
        address[] memory membersToAdd,
        address[] memory membersToRemove
    ) internal {
        bytes memory payload = abi.encodeWithSelector(
            IL1SecurityCouncilUpdateRouter.scheduleUpdateMembers.selector,
            abi.encode(membersToAdd, membersToRemove)
        );
        bytes32 salt = scm.calculateUpdateSalt(scm.updateNonce() - 1, payload);
        bytes32 id = scm.hashOperation(address(scm), 0, payload, bytes32(0), salt);

        // check operation is scheduled
        assertTrue(scm.isOperationPending(id), "operation pending");
        assertFalse(scm.isOperationReady(id), "operation not ready");

        // warp so it can be executed
        vm.warp(block.timestamp + minDelay);
        assertTrue(scm.isOperationReady(id), "operation ready");

        vm.recordLogs();
        // execute
        scm.execute(address(scm), 0, payload, bytes32(0), salt);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // check ArbSysL2ToL1Tx event was emitted with payload
        assertEq(
            entries[0].topics[0],
            keccak256("ArbSysL2ToL1Tx(address,address,uint256,bytes)"),
            "ArbSysL2ToL1Tx emitted"
        );
        bytes32 payloadFromEventLog = entries[0].topics[1];
        assertEq(payloadFromEventLog, keccak256(payload), "eq");
    }

    function removeFirstMember() internal {
        address memberToRemove = marchCohort[0];
        vm.prank(roles.memberRemovers[0]);
        scm.removeMember(memberToRemove);
    }
}
