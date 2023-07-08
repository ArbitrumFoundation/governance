// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../src/security-council-mgmt/SecurityCouncilManager.sol";
import "../../src/UpgradeExecRouterBuilder.sol";

import "../util/TestUtil.sol";
import "../util/MockArbSys.sol";

contract MockArbitrumTimelock {
    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );

    function getMinDelay() external view returns (uint256) {
        return uint256(123);
    }

    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual {
        emit CallScheduled(salt, 0, target, value, data, predecessor, delay);
    }
}

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

    address payable l2CoreGovTimelock;

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
        l2CoreGovTimelock = payable(address(new MockArbitrumTimelock()));

        scm.initialize(firstCohort, secondCohort, securityCouncils, roles, l2CoreGovTimelock, uerb);

        //
        // bytes memory code = vm.getDeployedCode("MockArbSys.sol:ArbSysMock");
        // address overrideAddress = address(0x0000000000000000000000000000000000000064);
        // vm.etch(overrideAddress, code);
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

    function testRemoveMemberAffordances() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.removeMember(rando);

        vm.prank(roles.memberRemovers[0]);
        vm.expectRevert("SecurityCouncilManager: member to remove not found");
        scm.removeMember(rando);
    }

    function testRemoveMember() public {
        vm.recordLogs();
        removeFirstMember();
        checkScheduleWasCalled();

        address[] memory remainingMembers = new address[](5);
        for (uint256 i = 1; i < firstCohort.length; i++) {
            remainingMembers[i - 1] = firstCohort[i];
        }
        assertTrue(
            TestUtil.areAddressArraysEqual(remainingMembers, scm.getFirstCohort()),
            "member removed from first chohort"
        );
    }

    function testAddMemberAffordances() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.addMember(memberToAdd, Cohort.FIRST);

        vm.prank(roles.memberAdder);
        vm.expectRevert("SecurityCouncilManager: cohort is full");
        scm.addMember(memberToAdd, Cohort.FIRST);

        removeFirstMember();

        vm.prank(roles.memberAdder);
        vm.expectRevert("SecurityCouncilManager: member already in first cohort");
        scm.addMember(firstCohort[1], Cohort.FIRST);
    }

    function testAddMember() public {
        removeFirstMember();
        vm.startPrank(roles.memberAdder);
        vm.recordLogs();
        scm.addMember(memberToAdd, Cohort.FIRST);
        checkScheduleWasCalled();
        vm.stopPrank();
        address[] memory newFirstCohort = new address[](6);
        for (uint256 i = 1; i < firstCohort.length; i++) {
            newFirstCohort[i - 1] = firstCohort[i];
        }
        newFirstCohort[5] = memberToAdd;

        assertTrue(
            TestUtil.areAddressArraysEqual(newFirstCohort, scm.getFirstCohort()),
            "member added to first chohort"
        );

        assertTrue(
            TestUtil.areAddressArraysEqual(secondCohort, scm.getSecondCohort()),
            "second cohort untouched"
        );
        // TODO test adding to second?
    }

    function testUpdateCohortAffordances() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.replaceCohort(newCohort, Cohort.FIRST);

        vm.startPrank(roles.cohortUpdator);
        address[] memory newSmallCohort = new address[](1);
        newSmallCohort[0] = rando;
        vm.expectRevert("SecurityCouncilManager: invalid cohort length");
        scm.replaceCohort(newSmallCohort, Cohort.FIRST);
        vm.stopPrank();
    }

    function testUpdateFirstCohort() public {
        vm.startPrank(roles.cohortUpdator);

        vm.recordLogs();
        scm.replaceCohort(newCohort, Cohort.FIRST);
        checkScheduleWasCalled();

        assertTrue(
            TestUtil.areAddressArraysEqual(newCohort, scm.getFirstCohort()), "first cohort updated"
        );

        assertTrue(
            TestUtil.areAddressArraysEqual(secondCohort, scm.getSecondCohort()),
            "second cohort untouched"
        );
    }

    function testUpdateSecondCohort() public {
        vm.startPrank(roles.cohortUpdator);

        vm.recordLogs();
        scm.replaceCohort(newCohort, Cohort.SECOND);
        checkScheduleWasCalled();

        assertTrue(
            TestUtil.areAddressArraysEqual(newCohort, scm.getSecondCohort()),
            "second cohort updated"
        );
        assertTrue(
            TestUtil.areAddressArraysEqual(firstCohort, scm.getFirstCohort()),
            "first cohort untouched"
        );
    }

    // // TODO: test rotator

    // // helpers
    function checkScheduleWasCalled() internal {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(
            entries[0].topics[0],
            keccak256("CallScheduled(bytes32,uint256,address,uint256,bytes,bytes32,uint256)"),
            "ArbSysL2ToL1Tx emitted"
        );
    }

    function removeFirstMember() internal {
        address memberToRemove = firstCohort[0];
        vm.prank(roles.memberRemovers[0]);
        scm.removeMember(memberToRemove);
    }
}
