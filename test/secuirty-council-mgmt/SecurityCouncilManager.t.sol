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
    address[] firstCohort = new address[](6);
    address[6] _firstCohort =
        [address(1111), address(1112), address(1113), address(1114), address(1114), address(1116)];

    address[] secondCohort = new address[](6);
    address[6] _secondCohort =
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
        memberRotator: address(4446),
        memberReplacer: address(4447)
    });

    address rando = address(6661);

    address memberToAdd = address(7771);

    address l1ArbitrumTimelock = address(8881);

    address payable l2CoreGovTimelock;

    uint256 l1TimelockMinDelay = uint256(1);
    ChainAndUpExecLocation[] chainAndUpExecLocation;
    SecurityCouncilData[] securityCouncils;

    SecurityCouncilData firstSC = SecurityCouncilData({
        securityCouncil: address(9991),
        updateAction: address(9992),
        chainId: 2
    });

    SecurityCouncilData scToAdd = SecurityCouncilData({
        securityCouncil: address(9993),
        updateAction: address(9994),
        chainId: 3
    });

    ChainAndUpExecLocation firstChainAndUpExecLocation = ChainAndUpExecLocation({
        chainId: 2,
        location: UpExecLocation({inbox: address(9993), upgradeExecutor: address(9994)})
    });

    ChainAndUpExecLocation secondChainAndUpExecLocation = ChainAndUpExecLocation({
        chainId: 3,
        location: UpExecLocation({inbox: address(9995), upgradeExecutor: address(9996)})
    });

    function setUp() public {
        chainAndUpExecLocation.push(firstChainAndUpExecLocation);
        chainAndUpExecLocation.push(secondChainAndUpExecLocation);
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

        securityCouncils.push(firstSC);
        scm.initialize(firstCohort, secondCohort, securityCouncils, roles, l2CoreGovTimelock, uerb);
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

    function testAddMemberToFirstCohort() public {
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
    }

    function testAddMemberToSecondCohort() public {
        vm.prank(roles.memberRemovers[0]);
        scm.removeMember(secondCohort[0]);

        vm.startPrank(roles.memberAdder);
        vm.recordLogs();
        scm.addMember(memberToAdd, Cohort.SECOND);
        checkScheduleWasCalled();
        vm.stopPrank();
        address[] memory newSecondCohort = new address[](6);
        for (uint256 i = 1; i < secondCohort.length; i++) {
            newSecondCohort[i - 1] = secondCohort[i];
        }
        newSecondCohort[5] = memberToAdd;

        assertTrue(
            TestUtil.areAddressArraysEqual(newSecondCohort, scm.getSecondCohort()),
            "member added to second chohort"
        );

        assertTrue(
            TestUtil.areAddressArraysEqual(firstCohort, scm.getFirstCohort()),
            "first cohort untouched"
        );
    }

    function testReplaceMemberAffordances() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.replaceMember(rando, rando);

        vm.startPrank(roles.memberReplacer);
        vm.expectRevert("SecurityCouncilManager: member to remove not found");
        scm.replaceMember(memberToAdd, rando);

        vm.expectRevert("SecurityCouncilManager: member already in first cohort");
        scm.replaceMember(firstCohort[0], firstCohort[1]);

        vm.expectRevert("SecurityCouncilManager: member already in second cohort");
        scm.replaceMember(firstCohort[0], secondCohort[0]);
        vm.stopPrank();
    }

    function testReplaceMemberInFirstCohort() public {
        vm.startPrank(roles.memberReplacer);
        vm.recordLogs();
        scm.replaceMember(firstCohort[0], memberToAdd);
        checkScheduleWasCalled();

        address[] memory newFirstCohortArray = new address[](6);
        newFirstCohortArray[0] = memberToAdd;
        for (uint256 i = 1; i < firstCohort.length; i++) {
            newFirstCohortArray[i] = firstCohort[i];
        }
        assertTrue(
            TestUtil.areAddressArraysEqual(newFirstCohortArray, scm.getFirstCohort()),
            "first cohort updated"
        );
        assertTrue(
            TestUtil.areAddressArraysEqual(secondCohort, scm.getSecondCohort()),
            "second cohort untouched"
        );
        vm.stopPrank();
    }

    function testReplaceMemberInSecondCohort() public {
        vm.startPrank(roles.memberReplacer);
        vm.recordLogs();
        scm.replaceMember(secondCohort[0], memberToAdd);
        checkScheduleWasCalled();
        address[] memory newSecondCohortArray = new address[](6);
        newSecondCohortArray[0] = memberToAdd;
        for (uint256 i = 1; i < secondCohort.length; i++) {
            newSecondCohortArray[i] = secondCohort[i];
        }
        assertTrue(
            TestUtil.areAddressArraysEqual(newSecondCohortArray, scm.getSecondCohort()),
            "second cohort updated"
        );
        assertTrue(
            TestUtil.areAddressArraysEqual(firstCohort, scm.getFirstCohort()),
            "first cohort untouched"
        );
        vm.stopPrank();
    }

    function testAddSCAffordances() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.addSecurityCouncil(scToAdd);

        vm.startPrank(roles.admin);
        vm.expectRevert("SecurityCouncilManager: security council already included");
        scm.addSecurityCouncil(firstSC);

        SecurityCouncilData memory scWithChainNotInRouter = SecurityCouncilData({
            securityCouncil: address(9991),
            updateAction: address(9992),
            chainId: 4
        });
        vm.expectRevert("SecurityCouncilManager: security council not in UpgradeExecRouterBuilder");
        scm.addSecurityCouncil(scWithChainNotInRouter);
        vm.stopPrank();
    }

    function testAddSC() public {
        uint256 len = scm.securityCouncilsLength();
        vm.prank(roles.admin);
        scm.addSecurityCouncil(scToAdd);
        assertEq(len + 1, scm.securityCouncilsLength(), "confimred new SC added");

        (address scAddress, address action, uint256 chainid) =
            scm.securityCouncils(scm.securityCouncilsLength() - 1);

        assertEq(scAddress, scToAdd.securityCouncil, "confimred new SC added");
        assertEq(chainid, scToAdd.chainId, "confimred new SC added");
    }

    function testRemoveSCAffordances() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.removeSecurityCouncil(firstSC);

        vm.prank(roles.admin);
        vm.expectRevert("SecurityCouncilManager: security council not found");
        scm.removeSecurityCouncil(scToAdd);
    }

    function testRemoveSeC() public {
        vm.prank(roles.admin);
        scm.removeSecurityCouncil(firstSC);
        assertEq(scm.securityCouncilsLength(), 0, "SC removed");
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

    function testUpdateRouterAffordacnes() public {
        UpgradeExecRouterBuilder newRouter = UpgradeExecRouterBuilder(TestUtil.deployStubContract());
        vm.prank(rando);
        vm.expectRevert();
        scm.setUpgradeExecRouterBuilder(newRouter);

        vm.prank(roles.admin);
        vm.expectRevert("SecurityCouncilManager: new router not a contract");
        scm.setUpgradeExecRouterBuilder(UpgradeExecRouterBuilder(rando));
    }

    function testUpdateRouter() public {
        UpgradeExecRouterBuilder newRouter = UpgradeExecRouterBuilder(TestUtil.deployStubContract());
        vm.prank(roles.admin);
        scm.setUpgradeExecRouterBuilder(UpgradeExecRouterBuilder(newRouter));
        assertEq(address(newRouter), address(scm.router()), "router set");
    }

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
