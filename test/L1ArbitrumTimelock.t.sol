// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/L1ArbitrumTimelock.sol";
import "./util/TestUtil.sol";
import "./util/InboxMock.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

import "forge-std/Test.sol";

contract Setter {
    uint256 public val;

    function setValue(uint256 _val) public {
        val = _val;
    }
}

contract L1ArbitrumTimelockTest is Test {
    address bridge = address(138);
    uint256 minDelay = 10;
    address l2Timelock = address(139);
    address outbox = address(140);
    address l1Council = address(141);

    function deploy() internal returns (L1ArbitrumTimelock) {
        L1ArbitrumTimelock timelock =
            L1ArbitrumTimelock(payable(TestUtil.deployProxy(address(new L1ArbitrumTimelock()))));

        return timelock;
    }

    function deployAndInitInbox() internal returns (L1ArbitrumTimelock, InboxMock) {
        L1ArbitrumTimelock l1Timelock = deploy();
        InboxMock inbox = new InboxMock(bridge);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        l1Timelock.initialize(minDelay, executors, address(inbox), l2Timelock);

        return (l1Timelock, inbox);
    }

    function deployAndInit() internal returns (L1ArbitrumTimelock) {
        (L1ArbitrumTimelock l1Timelock,) = deployAndInitInbox();
        return l1Timelock;
    }

    function testDoesDeploy() external {
        (L1ArbitrumTimelock l1Timelock, InboxMock inbox) = deployAndInitInbox();

        assertEq(l1Timelock.governanceChainInbox(), address(inbox), "inbox");
        assertEq(l1Timelock.l2Timelock(), l2Timelock, "timelock");
        assertEq(l1Timelock.hasRole(l1Timelock.PROPOSER_ROLE(), bridge), true, "bridge proposer");
        assertEq(l1Timelock.hasRole(l1Timelock.EXECUTOR_ROLE(), address(0)), true, "any executor");
    }

    function mockActiveOutbox(address activeOutbox, address l2ToL1Sender) internal {
        vm.mockCall(
            bridge, bytes.concat(IBridge(bridge).activeOutbox.selector), abi.encode(activeOutbox)
        );
        vm.mockCall(
            activeOutbox,
            bytes.concat(IOutbox(outbox).l2ToL1Sender.selector),
            abi.encode(l2ToL1Sender)
        );
    }

    function testDoesNotDeployZeroInbox() external {
        L1ArbitrumTimelock l1Timelock = deploy();
        InboxMock inbox = new InboxMock(bridge);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        vm.mockCall(
            address(inbox), bytes.concat(IInbox(address(inbox)).bridge.selector), abi.encode(bridge)
        );
        vm.expectRevert("L1ArbitrumTimelock: zero inbox");
        l1Timelock.initialize(minDelay, executors, address(0), l2Timelock);
    }

    function testDoesNotDeployZeroL2Timelock() external {
        L1ArbitrumTimelock l1Timelock = deploy();
        InboxMock inbox = new InboxMock(bridge);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        vm.mockCall(
            address(inbox), bytes.concat(IInbox(address(inbox)).bridge.selector), abi.encode(bridge)
        );
        vm.expectRevert("L1ArbitrumTimelock: zero l2 timelock");
        l1Timelock.initialize(minDelay, executors, address(inbox), address(0));
    }

    struct ScheduleArgs {
        address target;
        uint256 value;
        bytes payload;
        address[] targets;
        uint256[] values;
        bytes[] payloads;
        bytes32 salt;
        bytes32 predecessor;
    }

    function dummyScheduleArgs() internal pure returns (ScheduleArgs memory) {
        address target = address(1234);
        uint256 value = 10;
        bytes5 p = 0xde92eef460;
        bytes memory payload = bytes.concat(p);

        address[] memory targets = new address[](2);
        targets[0] = target;
        targets[1] = address(123_456);

        uint256[] memory values = new uint256[](2);
        values[0] = value;
        values[1] = 25;

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = payload;
        bytes4 p2 = 0x564a78bc;
        payloads[1] = bytes.concat(p2);

        bytes32 salt = keccak256(bytes("Test prop"));
        bytes32 predecessor = bytes32(0);
        return ScheduleArgs({
            target: target,
            value: value,
            payload: payload,
            targets: targets,
            values: values,
            payloads: payloads,
            salt: salt,
            predecessor: predecessor
        });
    }

    function scheduleAndRoll(
        L1ArbitrumTimelock l1Timelock,
        address target,
        uint256 value,
        bytes memory payload,
        bytes32 salt
    ) internal returns (bytes32) {
        mockActiveOutbox(outbox, l2Timelock);
        vm.prank(bridge);
        l1Timelock.schedule(target, value, payload, 0, salt, minDelay);

        vm.warp(block.timestamp + minDelay);

        bytes32 opId = l1Timelock.hashOperation(target, value, payload, 0, salt);

        return opId;
    }

    function testExecute() external {
        Setter setter = new Setter();
        uint256 setVal = 10;
        bytes memory data = abi.encodeWithSelector(setter.setValue.selector, setVal);
        bytes32 salt = keccak256(abi.encode("hi"));

        L1ArbitrumTimelock l1Timelock = deployAndInit();
        scheduleAndRoll(l1Timelock, address(setter), 0, data, salt);

        l1Timelock.execute(address(setter), 0, data, 0, salt);
        assertEq(setter.val(), setVal, "Set val");
    }

    struct RetryableData {
        address inbox;
        address l2Target;
        uint256 l2Value;
        uint256 gasLimit;
        uint256 maxFeePerGas;
        bytes data;
    }

    function testExecuteInbox() external {
        Setter setter = new Setter();
        L1ArbitrumTimelock l1Timelock = deployAndInit();
        InboxMock inbox = InboxMock(l1Timelock.governanceChainInbox());
        RetryableData memory rData = RetryableData({
            inbox: address(inbox),
            l2Target: address(235),
            l2Value: 10,
            gasLimit: 300_000,
            maxFeePerGas: 9 gwei,
            data: abi.encodeWithSelector(setter.setValue.selector, 10)
        });
        uint256 val = 105;
        bytes memory data = abi.encode(
            rData.inbox,
            rData.l2Target,
            rData.l2Value,
            rData.gasLimit,
            rData.maxFeePerGas,
            rData.data
        );
        bytes32 salt = keccak256(abi.encode("hi"));

        address magic = l1Timelock.RETRYABLE_TICKET_MAGIC();
        scheduleAndRoll(l1Timelock, magic, val, data, salt);

        vm.fee(21 gwei);
        uint256 submissionFee = inbox.calculateRetryableSubmissionFee(rData.data.length, 0);

        // set up the sender
        address payable sender = payable(address(678));
        uint256 extra = 150;
        uint256 execVal = submissionFee + (rData.maxFeePerGas * rData.gasLimit) + extra;
        sender.transfer(execVal);

        // l2value has to come from the timelock itself
        payable(address(l1Timelock)).transfer(rData.l2Value);

        vm.prank(sender);
        l1Timelock.execute{value: execVal}(magic, val, data, 0, salt);
        assertEq(inbox.msgNum(), 2, "Msg num not updated");
        assertEq(sender.balance, 0, "None returned");
    }

    function testExecuteInboxBatch() external {
        Setter setter = new Setter();
        L1ArbitrumTimelock l1Timelock = deployAndInit();
        InboxMock inbox = InboxMock(l1Timelock.governanceChainInbox());
        RetryableData memory rData = RetryableData({
            inbox: address(inbox),
            l2Target: address(235),
            l2Value: 10,
            gasLimit: 300_000,
            maxFeePerGas: 9 gwei,
            data: abi.encodeWithSelector(setter.setValue.selector, 10)
        });
        RetryableData memory rData2 = RetryableData({
            inbox: address(inbox),
            l2Target: address(236),
            l2Value: 11,
            gasLimit: 300_001,
            maxFeePerGas: 11 gwei,
            data: abi.encodeWithSelector(setter.setValue.selector, 11)
        });
        uint256[] memory vals = new uint256[](2);
        {
            uint256 val = 105;
            uint256 val2 = 106;
            vals[0] = val;
            vals[0] = val2;
        }
        bytes[] memory payloads = new bytes[](2);
        {
            bytes memory data = abi.encode(
                rData.inbox,
                rData.l2Target,
                rData.l2Value,
                rData.gasLimit,
                rData.maxFeePerGas,
                rData.data
            );
            bytes memory data2 = abi.encode(
                rData2.inbox,
                rData2.l2Target,
                rData2.l2Value,
                rData2.gasLimit,
                rData2.maxFeePerGas,
                rData2.data
            );
            payloads[0] = data;
            payloads[1] = data2;
        }
        bytes32 salt = keccak256(abi.encode("hi"));

        address[] memory tos = new address[](2);

        tos[0] = l1Timelock.RETRYABLE_TICKET_MAGIC();
        tos[1] = l1Timelock.RETRYABLE_TICKET_MAGIC();

        mockActiveOutbox(outbox, l2Timelock);
        vm.prank(bridge);
        l1Timelock.scheduleBatch(tos, vals, payloads, 0, salt, minDelay);

        vm.warp(block.timestamp + minDelay);

        vm.fee(21 gwei);
        uint256 submissionFee = inbox.calculateRetryableSubmissionFee(rData.data.length, 0);

        // set up the sender
        address payable sender = payable(address(678));
        uint256 execVal = (submissionFee * 2) + (rData.maxFeePerGas * rData.gasLimit)
            + (rData2.maxFeePerGas * rData2.gasLimit) + 13;
        sender.transfer(execVal);

        // l2value has to come from the timelock itself
        payable(address(l1Timelock)).transfer(rData.l2Value);
        payable(address(l1Timelock)).transfer(rData2.l2Value);

        vm.prank(sender);
        l1Timelock.executeBatch{value: execVal}(tos, vals, payloads, 0, salt);
        assertEq(inbox.msgNum(), 3, "Msg num not updated");
        assertEq(sender.balance, 0, "None returned");
        assertEq(address(l1Timelock).balance, 13, "Balance remaining");
    }

    function testExecuteInboxNotEnoughVal() external {
        Setter setter = new Setter();
        L1ArbitrumTimelock l1Timelock = deployAndInit();
        InboxMock inbox = InboxMock(l1Timelock.governanceChainInbox());
        RetryableData memory rData = RetryableData({
            inbox: address(inbox),
            l2Target: address(235),
            l2Value: 10,
            gasLimit: 300_000,
            maxFeePerGas: 9 gwei,
            data: abi.encodeWithSelector(setter.setValue.selector, 10)
        });
        uint256 val = 105;
        bytes memory data = abi.encode(
            rData.inbox,
            rData.l2Target,
            rData.l2Value,
            rData.gasLimit,
            rData.maxFeePerGas,
            rData.data
        );
        bytes32 salt = keccak256(abi.encode("hi"));

        address magic = l1Timelock.RETRYABLE_TICKET_MAGIC();
        scheduleAndRoll(l1Timelock, magic, val, data, salt);

        vm.fee(21 gwei);
        uint256 submissionFee = inbox.calculateRetryableSubmissionFee(rData.data.length, 0);

        // set up the sender
        address payable sender = payable(address(678));
        uint256 extra = 150;
        uint256 execVal = submissionFee + (rData.maxFeePerGas * rData.gasLimit) + extra;
        sender.transfer(execVal);

        // l2value has to come from the timelock itself
        payable(address(l1Timelock)).transfer(rData.l2Value);

        vm.expectRevert();
        vm.prank(sender);
        l1Timelock.execute{value: execVal - extra - 1}(magic, val, data, 0, salt);
    }

    function testExecuteInboxInvalidData() external {
        Setter setter = new Setter();
        L1ArbitrumTimelock l1Timelock = deployAndInit();
        InboxMock inbox = InboxMock(l1Timelock.governanceChainInbox());
        RetryableData memory rData = RetryableData({
            inbox: address(inbox),
            l2Target: address(235),
            l2Value: 10,
            gasLimit: 300_000,
            maxFeePerGas: 9 gwei,
            data: abi.encodeWithSelector(setter.setValue.selector, 10)
        });
        uint256 val = 105;
        bytes memory data = abi.encode(
            rData.inbox, rData.l2Target, rData.l2Value, rData.gasLimit, rData.maxFeePerGas
        );
        // rData.data //  - make the data invalid

        bytes32 salt = keccak256(abi.encode("hi"));
        address magic = l1Timelock.RETRYABLE_TICKET_MAGIC();
        scheduleAndRoll(l1Timelock, magic, val, data, salt);

        vm.fee(21 gwei);
        uint256 submissionFee = inbox.calculateRetryableSubmissionFee(rData.data.length, 0);

        // set up the sender
        address payable sender = payable(address(678));
        uint256 extra = 150;
        uint256 execVal =
            submissionFee + rData.l2Value + (rData.maxFeePerGas * rData.gasLimit) + extra;
        sender.transfer(execVal);

        vm.expectRevert();
        vm.prank(sender);
        l1Timelock.execute{value: execVal}(magic, val, data, 0, salt);
    }

    function testSchedule() external {
        L1ArbitrumTimelock l1Timelock = deployAndInit();
        ScheduleArgs memory sarg = dummyScheduleArgs();

        mockActiveOutbox(outbox, l2Timelock);
        vm.prank(bridge);
        l1Timelock.schedule(
            sarg.target, sarg.value, sarg.payload, sarg.predecessor, sarg.salt, minDelay
        );

        bytes32 opId = l1Timelock.hashOperation(
            sarg.target, sarg.value, sarg.payload, sarg.predecessor, sarg.salt
        );
        assertEq(l1Timelock.isOperation(opId), true, "is op");

        vm.prank(bridge);
        l1Timelock.scheduleBatch(
            sarg.targets,
            sarg.values,
            sarg.payloads,
            sarg.predecessor,
            keccak256(abi.encodePacked(sarg.salt)),
            minDelay
        );

        bytes32 batchOpId = l1Timelock.hashOperationBatch(
            sarg.targets,
            sarg.values,
            sarg.payloads,
            sarg.predecessor,
            keccak256(abi.encodePacked(sarg.salt))
        );
        assertEq(l1Timelock.isOperation(batchOpId), true, "is op");
    }

    function testScheduleFailsBadSender() external {
        L1ArbitrumTimelock l1Timelock = deployAndInit();
        ScheduleArgs memory sarg = dummyScheduleArgs();

        mockActiveOutbox(outbox, l2Timelock);
        vm.expectRevert("L1ArbitrumTimelock: not from bridge");
        l1Timelock.schedule(
            sarg.target, sarg.value, sarg.payload, sarg.predecessor, sarg.salt, minDelay
        );

        vm.expectRevert("L1ArbitrumTimelock: not from bridge");
        l1Timelock.scheduleBatch(
            sarg.targets,
            sarg.values,
            sarg.payloads,
            sarg.predecessor,
            keccak256(abi.encodePacked(sarg.salt)),
            minDelay
        );
    }

    function testScheduleFailsBadL2Timelock() external {
        L1ArbitrumTimelock l1Timelock = deployAndInit();
        ScheduleArgs memory sarg = dummyScheduleArgs();

        address wrongL2Timelock = address(1245);
        mockActiveOutbox(outbox, wrongL2Timelock);
        vm.expectRevert("L1ArbitrumTimelock: not from l2 timelock");
        vm.prank(bridge);
        l1Timelock.schedule(
            sarg.target, sarg.value, sarg.payload, sarg.predecessor, sarg.salt, minDelay
        );

        vm.expectRevert("L1ArbitrumTimelock: not from l2 timelock");
        vm.prank(bridge);
        l1Timelock.scheduleBatch(
            sarg.targets,
            sarg.values,
            sarg.payloads,
            sarg.predecessor,
            keccak256(abi.encodePacked(sarg.salt)),
            minDelay
        );
    }

    function testCancel() external {
        L1ArbitrumTimelock l1Timelock = deployAndInit();
        ScheduleArgs memory sarg = dummyScheduleArgs();

        mockActiveOutbox(outbox, l2Timelock);
        vm.prank(bridge);
        l1Timelock.schedule(
            sarg.target, sarg.value, sarg.payload, sarg.predecessor, sarg.salt, minDelay
        );

        bytes32 opId = l1Timelock.hashOperation(
            sarg.target, sarg.value, sarg.payload, sarg.predecessor, sarg.salt
        );
        assertEq(l1Timelock.isOperation(opId), true, "is op");

        // L1GovernanceFactory will set l1Council as canceller on timelock
        l1Timelock.grantRole(l1Timelock.CANCELLER_ROLE(), l1Council);

        vm.prank(l1Council);
        l1Timelock.cancel(opId);

        assertEq(l1Timelock.isOperation(opId), false, "is op");
    }

    function testCancelFailsBadSender() external {
        L1ArbitrumTimelock l1Timelock = deployAndInit();
        ScheduleArgs memory sarg = dummyScheduleArgs();

        mockActiveOutbox(outbox, l2Timelock);
        vm.prank(bridge);
        l1Timelock.schedule(
            sarg.target, sarg.value, sarg.payload, sarg.predecessor, sarg.salt, minDelay
        );

        bytes32 opId = l1Timelock.hashOperation(
            sarg.target, sarg.value, sarg.payload, sarg.predecessor, sarg.salt
        );
        assertEq(l1Timelock.isOperation(opId), true, "is op");

        // cancel should revert when called from bridge
        address account = address(bridge);
        bytes32 role = l1Timelock.CANCELLER_ROLE();
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(uint160(account), 20),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(role), 32)
            )
        );

        vm.prank(bridge);
        l1Timelock.cancel(opId);
    }
}
