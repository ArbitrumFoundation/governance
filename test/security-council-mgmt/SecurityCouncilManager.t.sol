// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../src/security-council-mgmt/SecurityCouncilManager.sol";
import "../../src/UpgradeExecRouteBuilder.sol";
import "../../src/security-council-mgmt/governors/SecurityCouncilNomineeElectionGovernor.sol";
import "../../src/security-council-mgmt/governors/SecurityCouncilMemberElectionGovernor.sol";
import "../../src/L2ArbitrumToken.sol";

import "../util/TestUtil.sol";
import "../util/MockArbSys.sol";
import "../../src/security-council-mgmt/Common.sol";
import "./governors/SecurityCouncilNomineeElectionGovernor.t.sol";

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

    function getMinDelay() external pure returns (uint256) {
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
        [address(1111), address(1112), address(1113), address(1114), address(1115), address(1116)];

    address[] secondCohort = new address[](6);
    address[6] _secondCohort =
        [address(2221), address(2222), address(2223), address(2224), address(2225), address(2226)];

    address[] newCohort = new address[](6);
    address[6] _newCohort =
        [address(3331), address(3332), address(3333), address(3334), address(3335), address(3336)];

    address[] newCohortWithADup = new address[](6);
    address dup = address(3335);
    address[6] _newCohortWithADup =
        [address(3331), address(3332), address(3333), address(3334), dup, dup];

    SecurityCouncilManager scm;
    UpgradeExecRouteBuilder uerb;
    address[] memberRemovers = new address[](2);
    address memberRemover1 = address(4444);
    address memberRemover2 = address(4445);
    uint256 minRotationPeriod = 1 weeks;
    address minRotationPeriodSetter = address(4450);

    SecurityCouncilManagerRoles roles = SecurityCouncilManagerRoles({
        admin: address(4441),
        cohortUpdator: address(4442),
        memberAdder: address(4443),
        memberRemovers: memberRemovers,
        memberRotator: address(4446),
        memberReplacer: address(4447),
        minRotationPeriodSetter: minRotationPeriodSetter
    });

    address rando = address(6661);

    address memberToAdd = address(7771);
    uint256 pk1 = 7772;
    address memberToRotate1 = vm.addr(pk1);
    uint256 pk2 = 7773;
    address memberToRotate2 = vm.addr(pk2);

    address l1ArbitrumTimelock = address(8881);
    address nomineeVetter = address(8882);

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

    address[] bothCohorts;

    address memberElectionGovernor;
    address nomineeElectionGovernor;
    L2ArbitrumToken token;

    function setUp() public {
        chainAndUpExecLocation.push(firstChainAndUpExecLocation);
        chainAndUpExecLocation.push(secondChainAndUpExecLocation);
        uerb = new UpgradeExecRouteBuilder({
            _upgradeExecutors: chainAndUpExecLocation,
            _l1ArbitrumTimelock: l1ArbitrumTimelock,
            _l1TimelockMinDelay: l1TimelockMinDelay
        });
        for (uint256 i = 0; i < 6; i++) {
            secondCohort[i] = _secondCohort[i];
            firstCohort[i] = _firstCohort[i];
            bothCohorts.push(_firstCohort[i]);
            bothCohorts.push(_secondCohort[i]);
            newCohort[i] = _newCohort[i];
            newCohortWithADup[i] = _newCohortWithADup[i];
        }
        address prox = TestUtil.deployProxy(address(new SecurityCouncilManager()));
        scm = SecurityCouncilManager(payable(prox));
        l2CoreGovTimelock = payable(address(new MockArbitrumTimelock()));

        token = L2ArbitrumToken(payable(TestUtil.deployProxy(address(new L2ArbitrumToken()))));
        token.initialize(address(137), 10_000_000_000, address(this));

        SecurityCouncilMemberElectionGovernor memGov = SecurityCouncilMemberElectionGovernor(
            payable(TestUtil.deployProxy(address(new SecurityCouncilMemberElectionGovernor())))
        );
        SecurityCouncilNomineeElectionGovernor nomGov = SecurityCouncilNomineeElectionGovernor(
            payable(TestUtil.deployProxy(address(new SecurityCouncilNomineeElectionGovernor())))
        );

        SecurityCouncilNomineeElectionGovernor.InitParams memory initParams =
        SecurityCouncilNomineeElectionGovernor.InitParams(
            Date(2000, 1, 1, 1), 3, nomineeVetter, scm, memGov, token, address(0), 20, 20
        );
        nomGov.initialize(initParams);
        memGov.initialize(nomGov, scm, token, address(10), 10, 5);

        roles.cohortUpdator = address(memGov);
        memberElectionGovernor = address(memGov);
        nomineeElectionGovernor = address(nomGov);

        securityCouncils.push(firstSC);
        scm.initialize(
            firstCohort,
            secondCohort,
            securityCouncils,
            roles,
            l2CoreGovTimelock,
            uerb,
            minRotationPeriod
        );
    }

    function testInitialization() public {
        vm.expectRevert("Initializable: contract is already initialized");
        scm.initialize(
            firstCohort,
            secondCohort,
            securityCouncils,
            roles,
            l2CoreGovTimelock,
            uerb,
            minRotationPeriod
        );

        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(firstCohort, scm.getFirstCohort()),
            "first cohort set"
        );
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(secondCohort, scm.getSecondCohort()),
            "second cohort set"
        );

        assertTrue(scm.hasRole(scm.DEFAULT_ADMIN_ROLE(), roles.admin), "admin role set");
        assertTrue(
            scm.hasRole(scm.COHORT_REPLACER_ROLE(), roles.cohortUpdator),
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
        assertEq(minRotationPeriod, scm.minRotationPeriod(), "minRotationPeriod set");

        assertEq(address(uerb), address(scm.router()), "exec router set");
        assertEq(scm.NAME_HASH(), keccak256(bytes("SecurityCouncilManager")));
        assertEq(scm.VERSION_HASH(), keccak256(bytes("1")));
    }

    function testRemoveMemberAffordances() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.removeMember(rando);

        vm.prank(roles.memberRemovers[0]);
        vm.expectRevert(abi.encodeWithSelector(ISecurityCouncilManager.NotAMember.selector, rando));
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
            TestUtil.areUniqueAddressArraysEqual(remainingMembers, scm.getFirstCohort()),
            "member removed from first chohort"
        );
    }

    function testRemoveMemberRotated() public {
        address memberToRemove = firstCohort[0];
        bytes32 digest = scm.getRotateMemberHash(memberToRemove, scm.rotationNonce(memberToRemove));
        bytes memory signature = sign(pk1, digest);
        vm.prank(memberToRemove);
        scm.rotateMember(memberToRotate1, memberElectionGovernor, signature);

        vm.recordLogs();
        vm.prank(roles.memberRemovers[0]);
        scm.removeMember(memberToRemove);
        checkScheduleWasCalled();

        address[] memory remainingMembers = new address[](5);
        for (uint256 i = 1; i < firstCohort.length; i++) {
            remainingMembers[i - 1] = firstCohort[i];
        }
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(remainingMembers, scm.getFirstCohort()),
            "member removed from first chohort"
        );
    }

    function testAddMemberSpecialAddresses() public {
        vm.prank(roles.memberAdder);
        vm.expectRevert(ZeroAddress.selector);
        scm.addMember(address(0), Cohort.FIRST);
    }

    function testAddMemberAffordances() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.addMember(memberToAdd, Cohort.FIRST);

        vm.prank(roles.memberAdder);
        vm.expectRevert(
            abi.encodeWithSelector(ISecurityCouncilManager.CohortFull.selector, Cohort.FIRST)
        );
        scm.addMember(memberToAdd, Cohort.FIRST);

        removeFirstMember();

        vm.prank(roles.memberAdder);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISecurityCouncilManager.MemberInCohort.selector, firstCohort[1], Cohort.FIRST
            )
        );
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
            TestUtil.areUniqueAddressArraysEqual(newFirstCohort, scm.getFirstCohort()),
            "member added to first chohort"
        );

        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(secondCohort, scm.getSecondCohort()),
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
            TestUtil.areUniqueAddressArraysEqual(newSecondCohort, scm.getSecondCohort()),
            "member added to second chohort"
        );

        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(firstCohort, scm.getFirstCohort()),
            "first cohort untouched"
        );
    }

    function testReplaceMemberAffordances() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.replaceMember(rando, rando);

        vm.startPrank(roles.memberReplacer);
        vm.expectRevert(
            abi.encodeWithSelector(ISecurityCouncilManager.NotAMember.selector, memberToAdd)
        );
        scm.replaceMember(memberToAdd, rando);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISecurityCouncilManager.MemberInCohort.selector, firstCohort[1], Cohort.FIRST
            )
        );
        scm.replaceMember(firstCohort[0], firstCohort[1]);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISecurityCouncilManager.MemberInCohort.selector, secondCohort[0], Cohort.SECOND
            )
        );
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
            TestUtil.areUniqueAddressArraysEqual(newFirstCohortArray, scm.getFirstCohort()),
            "first cohort updated"
        );
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(secondCohort, scm.getSecondCohort()),
            "second cohort untouched"
        );
        vm.stopPrank();
    }

    function testReplaceMemberInFirstCohortAfterRotation() public {
        bytes32 digest = scm.getRotateMemberHash(firstCohort[0], scm.rotationNonce(firstCohort[0]));
        bytes memory signature = sign(pk1, digest);
        vm.prank(firstCohort[0]);
        scm.rotateMember(memberToRotate1, memberElectionGovernor, signature);

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
            TestUtil.areUniqueAddressArraysEqual(newFirstCohortArray, scm.getFirstCohort()),
            "first cohort updated"
        );
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(secondCohort, scm.getSecondCohort()),
            "second cohort untouched"
        );
        vm.stopPrank();
    }

    function testReplaceMemberInSecondCohort() public {
        bytes32 digest =
            scm.getRotateMemberHash(secondCohort[0], scm.rotationNonce(secondCohort[0]));
        bytes memory signature = sign(pk2, digest);
        vm.prank(secondCohort[0]);
        scm.rotateMember(memberToRotate2, memberElectionGovernor, signature);

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
            TestUtil.areUniqueAddressArraysEqual(newSecondCohortArray, scm.getSecondCohort()),
            "second cohort updated"
        );
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(firstCohort, scm.getFirstCohort()),
            "first cohort untouched"
        );
        vm.stopPrank();
    }

    function testReplaceMemberInSecondCohortAfterRotation() public {
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
            TestUtil.areUniqueAddressArraysEqual(newSecondCohortArray, scm.getSecondCohort()),
            "second cohort updated"
        );
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(firstCohort, scm.getFirstCohort()),
            "first cohort untouched"
        );
        vm.stopPrank();
    }

    function sign(uint256 privKey, bytes32 h) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, h);
        return abi.encodePacked(r, s, v);
    }

    function checkCohortChange(address newMember, uint256 index, address[] memory cohort, Cohort c)
        public
    {
        address[] memory newSecondCohortArray = new address[](6);
        for (uint256 i = 0; i < cohort.length; i++) {
            newSecondCohortArray[i] = cohort[i];
        }
        newSecondCohortArray[index] = newMember;
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(
                newSecondCohortArray,
                c == Cohort.FIRST ? scm.getFirstCohort() : scm.getSecondCohort()
            ),
            "cohort updated"
        );
    }

    function testRotateMember() public {
        address originalMember = secondCohort[1];
        uint256 startTime = 5678;
        vm.warp(startTime);

        bytes32 digest = scm.getRotateMemberHash(originalMember, scm.rotationNonce(originalMember));
        bytes memory signature = sign(pk1, digest);
        uint256 startNonce = scm.rotationNonce(originalMember);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISecurityCouncilManager.InvalidNewAddress.selector,
                0x00e6008973a133b0e603275498f18321534c3721f3
            )
        );
        vm.prank(secondCohort[2]);
        scm.rotateMember(memberToRotate1, memberElectionGovernor, signature);

        vm.expectRevert(
            abi.encodeWithSelector(ISecurityCouncilManager.GovernorNotReplacer.selector)
        );
        vm.prank(originalMember);
        scm.rotateMember(memberToRotate1, address(137), signature);

        vm.recordLogs();
        vm.prank(originalMember);
        scm.rotateMember(memberToRotate1, memberElectionGovernor, signature);
        assertEq(startNonce + 1, scm.rotationNonce(originalMember), "nonce 1");
        checkScheduleWasCalled();
        checkCohortChange(memberToRotate1, 1, secondCohort, Cohort.SECOND);
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(firstCohort, scm.getFirstCohort()),
            "first cohort untouched"
        );
        assertEq(scm.lastRotated(memberToRotate1), startTime, "Member 1 last rotated");

        bytes32 digest1 =
            scm.getRotateMemberHash(memberToRotate1, scm.rotationNonce(memberToRotate1));
        bytes memory signature1 = sign(pk2, digest1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISecurityCouncilManager.RotationTooSoon.selector,
                memberToRotate1,
                startTime + minRotationPeriod
            )
        );
        vm.prank(memberToRotate1);
        scm.rotateMember(memberToRotate1, memberElectionGovernor, signature1);

        vm.warp(startTime + minRotationPeriod - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISecurityCouncilManager.RotationTooSoon.selector,
                memberToRotate1,
                startTime + minRotationPeriod
            )
        );
        vm.prank(memberToRotate1);
        scm.rotateMember(memberToRotate1, memberElectionGovernor, signature1);

        vm.warp(startTime + minRotationPeriod);

        startNonce = scm.rotationNonce(memberToRotate1);
        vm.recordLogs();
        vm.prank(memberToRotate1);
        scm.rotateMember(memberToRotate2, memberElectionGovernor, signature1);
        assertEq(startNonce + 1, scm.rotationNonce(memberToRotate1), "nonce 2");
        checkScheduleWasCalled();
        checkCohortChange(memberToRotate2, 1, secondCohort, Cohort.SECOND);
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(firstCohort, scm.getFirstCohort()),
            "first cohort untouched 2"
        );
        assertEq(
            scm.lastRotated(memberToRotate2), startTime + minRotationPeriod, "Member 2 last rotated"
        );
    }

    function addAllContendersAndVote(uint256 proposalId) public {
        SecurityCouncilNomineeElectionGovernor nGov =
            SecurityCouncilNomineeElectionGovernor(payable(nomineeElectionGovernor));
        SigUtils sigUtils = new SigUtils(nomineeElectionGovernor);
        token.delegate(address(this));

        for (uint256 i = 0; i < 6; i++) {
            bytes memory sig = sigUtils.signAddContenderMessage(proposalId, i + 1000);
            nGov.addContender(proposalId, sig);
        }
        vm.roll(nGov.proposalDeadline(proposalId));
        for (uint256 i = 0; i < 6; i++) {
            nGov.castVoteWithReasonAndParams({
                proposalId: proposalId,
                support: 1,
                reason: "",
                params: abi.encode(vm.addr(i + 1000), 20_000_000)
            });
        }
    }

    function execProp(uint256 proposalId) public {
        SecurityCouncilNomineeElectionGovernor nGov =
            SecurityCouncilNomineeElectionGovernor(payable(nomineeElectionGovernor));
        vm.roll(
            SecurityCouncilNomineeElectionGovernorTiming(payable(address(nomineeElectionGovernor)))
                .proposalVettingDeadline(proposalId) + 1
        );
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory callDatas,
            string memory description
        ) = nGov.getProposeArgs(nGov.electionCount() - 1);
        nGov.execute(targets, values, callDatas, keccak256(bytes(description)));
    }

    function testRotateMemberNotContender() public {
        address originalMember = secondCohort[1];
        uint256 startTime = SecurityCouncilNomineeElectionGovernor(payable(nomineeElectionGovernor))
            .electionToTimestamp(0);
        vm.warp(startTime);

        // start an election and add a contender
        uint256 proposalId = SecurityCouncilNomineeElectionGovernor(
            payable(nomineeElectionGovernor)
        ).createElection();
        SecurityCouncilNomineeElectionGovernor(payable(nomineeElectionGovernor)).addContender(
            proposalId,
            new SigUtils(nomineeElectionGovernor).signAddContenderMessage(proposalId, pk1)
        );

        bytes memory signature =
            sign(pk1, scm.getRotateMemberHash(originalMember, scm.rotationNonce(originalMember)));
        bytes memory signature2 =
            sign(pk2, scm.getRotateMemberHash(originalMember, scm.rotationNonce(originalMember)));
        uint256 startNonce = scm.rotationNonce(originalMember);

        // replace in other cohort in ongoing election does not work
        vm.expectRevert(
            abi.encodeWithSelector(
                ISecurityCouncilManager.NewMemberIsContender.selector, proposalId, memberToRotate1
            )
        );
        vm.prank(originalMember);
        scm.rotateMember(memberToRotate1, memberElectionGovernor, signature);

        uint256 snap = vm.snapshot();

        addAllContendersAndVote(proposalId);

        // check that we cant rotate to a nominee
        vm.roll(
            SecurityCouncilNomineeElectionGovernor(payable(nomineeElectionGovernor))
                .proposalDeadline(proposalId) + 1
        );
        vm.prank(nomineeVetter);
        SecurityCouncilNomineeElectionGovernor(payable(nomineeElectionGovernor)).excludeNominee(
            proposalId, vm.addr(1004)
        );
        vm.prank(nomineeVetter);
        SecurityCouncilNomineeElectionGovernor(payable(nomineeElectionGovernor)).includeNominee(
            proposalId, memberToRotate2
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ISecurityCouncilManager.NewMemberIsNominee.selector, proposalId, memberToRotate2
            )
        );
        vm.prank(originalMember);
        scm.rotateMember(memberToRotate2, memberElectionGovernor, signature2);

        execProp(proposalId);
        assertEq(
            uint8(IGovernorUpgradeable(nomineeElectionGovernor).state(proposalId)),
            uint8(IGovernorUpgradeable.ProposalState.Executed),
            "Not executed"
        );
        vm.roll(block.number + 1);
        assertEq(
            uint8(IGovernorUpgradeable(memberElectionGovernor).state(proposalId)),
            uint8(IGovernorUpgradeable.ProposalState.Active),
            "Not active"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ISecurityCouncilManager.NewMemberIsContender.selector, proposalId, memberToRotate1
            )
        );
        vm.prank(originalMember);
        scm.rotateMember(memberToRotate1, memberElectionGovernor, signature);

        vm.revertTo(snap);

        // replacing that member with one in the same cohort does work
        bytes memory signatureA =
            sign(pk1, scm.getRotateMemberHash(firstCohort[1], scm.rotationNonce(firstCohort[1])));
        startNonce = scm.rotationNonce(firstCohort[1]);
        vm.prank(firstCohort[1]);
        scm.rotateMember(memberToRotate1, memberElectionGovernor, signatureA);
        assertEq(startNonce + 1, scm.rotationNonce(firstCohort[1]), "nonce 1");
        checkCohortChange(memberToRotate1, 1, firstCohort, Cohort.FIRST);
        vm.revertTo(snap);

        bytes memory signature1 =
            sign(pk2, scm.getRotateMemberHash(originalMember, scm.rotationNonce(originalMember)));
        startNonce = scm.rotationNonce(originalMember);

        vm.recordLogs();
        vm.prank(originalMember);
        scm.rotateMember(memberToRotate2, memberElectionGovernor, signature1);
        assertEq(startNonce + 1, scm.rotationNonce(originalMember), "nonce 1");
        checkScheduleWasCalled();
        checkCohortChange(memberToRotate2, 1, secondCohort, Cohort.SECOND);
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(firstCohort, scm.getFirstCohort()),
            "first cohort untouched"
        );
        assertEq(scm.lastRotated(memberToRotate2), startTime, "Member 1 last rotated");
    }

    event MinRotationPeriodSet(uint256 minRotationPeriod);

    function testPostUpgradeInit() public {
        ProxyAdmin pa = new ProxyAdmin();
        SecurityCouncilManager logic = new SecurityCouncilManager();
        SecurityCouncilManager s = SecurityCouncilManager(
            address(new TransparentUpgradeableProxy(address(logic), address(pa), ""))
        );
        uint256 mr = 25;
        address mrs = address(88_766);

        vm.expectRevert();
        vm.prank(address(137));
        TransparentUpgradeableProxy(payable(address(s))).upgradeToAndCall(
            address(logic), abi.encodeCall(s.postUpgradeInit, (mr, mrs))
        );

        vm.expectEmit(true, true, true, true);
        emit MinRotationPeriodSet(mr);
        vm.prank(address(pa));
        TransparentUpgradeableProxy(payable(address(s))).upgradeToAndCall(
            address(logic), abi.encodeCall(s.postUpgradeInit, (mr, mrs))
        );
        assertEq(s.minRotationPeriod(), mr, "Min rotation updated");
        assertTrue(
            s.hasRole(s.MIN_ROTATION_PERIOD_SETTER_ROLE(), mrs), "Min rotation period setter role"
        );
        assertEq(s.NAME_HASH(), keccak256(bytes("SecurityCouncilManager")));
        assertEq(s.VERSION_HASH(), keccak256(bytes("1")));

        vm.expectRevert("MIN_ROTATION_ALREADY_SET");
        vm.prank(address(pa));
        TransparentUpgradeableProxy(payable(address(s))).upgradeToAndCall(
            address(logic), abi.encodeCall(s.postUpgradeInit, (mr, mrs))
        );
    }

    function testSetMinRotationPeriod() public {
        vm.expectRevert();
        scm.setMinRotationPeriod(27);

        vm.prank(minRotationPeriodSetter);
        scm.setMinRotationPeriod(27);
        assertEq(scm.minRotationPeriod(), 27, "Min rotation period set");
    }

    function testAddSCAffordances() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.addSecurityCouncil(scToAdd);

        vm.startPrank(roles.admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISecurityCouncilManager.SecurityCouncilAlreadyInRouter.selector, firstSC
            )
        );
        scm.addSecurityCouncil(firstSC);

        SecurityCouncilData memory scWithChainNotInRouter = SecurityCouncilData({
            securityCouncil: address(9991),
            updateAction: address(9992),
            chainId: 4
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                ISecurityCouncilManager.SecurityCouncilNotInRouter.selector, scWithChainNotInRouter
            )
        );
        scm.addSecurityCouncil(scWithChainNotInRouter);
        vm.stopPrank();
    }

    function testAddSC() public {
        uint256 len = scm.securityCouncilsLength();
        vm.prank(roles.admin);
        scm.addSecurityCouncil(scToAdd);
        assertEq(len + 1, scm.securityCouncilsLength(), "confimred new SC added");

        (address scAddress,, uint256 chainid) =
            scm.securityCouncils(scm.securityCouncilsLength() - 1);

        assertEq(scAddress, scToAdd.securityCouncil, "confimred new SC added");
        assertEq(chainid, scToAdd.chainId, "confimred new SC added");
    }

    function testRemoveSCAffordances() public {
        vm.prank(rando);
        vm.expectRevert();
        scm.removeSecurityCouncil(firstSC);

        vm.prank(roles.admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISecurityCouncilManager.SecurityCouncilNotInManager.selector, scToAdd
            )
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(
                ISecurityCouncilManager.InvalidNewCohortLength.selector,
                newSmallCohort,
                newCohort.length
            )
        );
        scm.replaceCohort(newSmallCohort, Cohort.FIRST);
        vm.stopPrank();
    }

    function testUpdateFirstCohort() public {
        vm.startPrank(roles.cohortUpdator);

        vm.recordLogs();
        scm.replaceCohort(newCohort, Cohort.FIRST);
        checkScheduleWasCalled();

        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(newCohort, scm.getFirstCohort()),
            "first cohort updated"
        );

        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(secondCohort, scm.getSecondCohort()),
            "second cohort untouched"
        );
    }

    function testUpdateSecondCohort() public {
        vm.startPrank(roles.cohortUpdator);

        vm.recordLogs();
        scm.replaceCohort(newCohort, Cohort.SECOND);
        checkScheduleWasCalled();

        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(newCohort, scm.getSecondCohort()),
            "second cohort updated"
        );
        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(firstCohort, scm.getFirstCohort()),
            "first cohort untouched"
        );
    }

    function testCantUpdateCohortWithADup() public {
        vm.startPrank(roles.cohortUpdator);
        vm.expectRevert(
            abi.encodeWithSelector(ISecurityCouncilManager.MemberInCohort.selector, dup, 1)
        );
        scm.replaceCohort(newCohortWithADup, Cohort.SECOND);
    }

    function testUpdateRouterAffordances() public {
        UpgradeExecRouteBuilder newRouter = UpgradeExecRouteBuilder(TestUtil.deployStubContract());
        vm.prank(rando);
        vm.expectRevert();
        scm.setUpgradeExecRouteBuilder(newRouter);

        vm.prank(roles.admin);
        vm.expectRevert(abi.encodeWithSelector(NotAContract.selector, rando));
        scm.setUpgradeExecRouteBuilder(UpgradeExecRouteBuilder(rando));
    }

    function testUpdateRouter() public {
        UpgradeExecRouteBuilder newRouter = UpgradeExecRouteBuilder(TestUtil.deployStubContract());
        vm.prank(roles.admin);
        scm.setUpgradeExecRouteBuilder(UpgradeExecRouteBuilder(newRouter));
        assertEq(address(newRouter), address(scm.router()), "router set");
    }

    function testCohortMethods() public {
        assertTrue(scm.firstCohortIncludes(firstCohort[0]), "firstCohortIncludes works");
        assertFalse(scm.firstCohortIncludes(secondCohort[0]), "firstCohortIncludes works");
        assertTrue(scm.secondCohortIncludes(secondCohort[0]), "secondCohortIncludes works");
        assertFalse(scm.secondCohortIncludes(firstCohort[0]), "secondCohortIncludes works");

        assertTrue(
            TestUtil.areUniqueAddressArraysEqual(scm.getBothCohorts(), bothCohorts),
            "getBothCohorts works"
        );
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
