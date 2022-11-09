// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/L1ArbitrumTimelock.sol";
import "./util/TestUtil.sol";

import "forge-std/Test.sol";

contract Setter {
    uint256 public val;

    function setValue(uint256 _val) public {
        val = _val;
    }
}

contract InboxMock is IInboxSubmissionFee {
    uint256 public msgNum = 1;
    address public bridge;

    constructor(address _bridge) {
        bridge = _bridge;
    }

    /// @dev msg.value sent to the inbox isn't high enough
    error InsufficientValue(uint256 expected, uint256 actual);

    /// @dev submission cost provided isn't enough to create retryable ticket
    error InsufficientSubmissionCost(uint256 expected, uint256 actual);

    error RetryableData(
        address from,
        address to,
        uint256 l2CallValue,
        uint256 deposit,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        bytes data
    );

    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee)
        public
        view
        returns (uint256)
    {
        // Use current block basefee if baseFee parameter is 0
        return (1400 + 6 * dataLength) * (baseFee == 0 ? block.basefee : baseFee);
    }

    function createRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        bytes calldata data
    ) external payable returns (uint256) {
        if (msg.value < (maxSubmissionCost + l2CallValue + gasLimit * maxFeePerGas)) {
            revert InsufficientValue(
                maxSubmissionCost + l2CallValue + gasLimit * maxFeePerGas, msg.value
            );
        }

        if (gasLimit == 1 || maxFeePerGas == 1) {
            revert RetryableData(
                msg.sender,
                to,
                l2CallValue,
                msg.value,
                maxSubmissionCost,
                excessFeeRefundAddress,
                callValueRefundAddress,
                gasLimit,
                maxFeePerGas,
                data
            );
        }

        uint256 submissionFee = calculateRetryableSubmissionFee(data.length, block.basefee);
        if (maxSubmissionCost < submissionFee) {
            revert InsufficientSubmissionCost(submissionFee, maxSubmissionCost);
        }

        return msgNum++;
    }
}

contract L1ArbitrumTimelockTest is Test {
    address bridge = address(138);
    uint256 minDelay = 10;
    address l2Timelock = address(139);
    address outbox = address(140);

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

        l1Timelock.initialize(minDelay, new address[](0), executors, address(inbox), l2Timelock);

        return (l1Timelock, inbox);
    }

    function deployAndInit() internal returns (L1ArbitrumTimelock) {
        (L1ArbitrumTimelock l1Timelock,) = deployAndInitInbox();
        return l1Timelock;
    }

    function testDoesDeploy() external {
        (L1ArbitrumTimelock l1Timelock, InboxMock inbox) = deployAndInitInbox();

        assertEq(l1Timelock.inbox(), address(inbox), "inbox");
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
        l1Timelock.initialize(minDelay, new address[](0), executors, address(0), l2Timelock);
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
        l1Timelock.initialize(minDelay, new address[](0), executors, address(inbox), address(0));
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
        address l2Target;
        uint256 l2Value;
        address excessFeeRefundAddress;
        address callValueRefundAddress;
        uint256 gasLimit;
        uint256 maxFeePerGas;
        bytes data;
    }

    function testExecuteInbox() external {
        Setter setter = new Setter();
        RetryableData memory rData = RetryableData({
            l2Target: address(235),
            l2Value: 10,
            excessFeeRefundAddress: address(236),
            callValueRefundAddress: address(237),
            gasLimit: 300_000,
            maxFeePerGas: 9 gwei,
            data: abi.encodeWithSelector(setter.setValue.selector, 10)
        });
        uint256 val = 105;
        bytes memory data = abi.encode(
            rData.l2Target,
            rData.l2Value,
            rData.excessFeeRefundAddress,
            rData.callValueRefundAddress,
            rData.gasLimit,
            rData.maxFeePerGas,
            rData.data
        );
        bytes32 salt = keccak256(abi.encode("hi"));

        L1ArbitrumTimelock l1Timelock = deployAndInit();
        InboxMock inbox = InboxMock(l1Timelock.inbox());
        scheduleAndRoll(l1Timelock, address(inbox), val, data, salt);

        vm.fee(21 gwei);
        uint256 submissionFee = inbox.calculateRetryableSubmissionFee(rData.data.length, 0);

        // set up the sender
        address payable sender = payable(address(678));
        uint256 extra = 150;
        sender.transfer(
            submissionFee + rData.l2Value + (rData.maxFeePerGas * rData.gasLimit) + extra
        );

        vm.prank(sender);
        l1Timelock.execute{
            value: submissionFee + rData.l2Value + (rData.maxFeePerGas * rData.gasLimit) + extra
        }(address(inbox), val, data, 0, salt);
        assertEq(inbox.msgNum(), 2, "Msg num not updated");
        assertEq(sender.balance, extra, "Extra returned");
    }

    function testExecuteInboxNotEnoughVal() external {
        Setter setter = new Setter();
        RetryableData memory rData = RetryableData({
            l2Target: address(235),
            l2Value: 10,
            excessFeeRefundAddress: address(236),
            callValueRefundAddress: address(237),
            gasLimit: 300_000,
            maxFeePerGas: 9 gwei,
            data: abi.encodeWithSelector(setter.setValue.selector, 10)
        });
        uint256 val = 105;
        bytes memory data = abi.encode(
            rData.l2Target,
            rData.l2Value,
            rData.excessFeeRefundAddress,
            rData.callValueRefundAddress,
            rData.gasLimit,
            rData.maxFeePerGas,
            rData.data
        );
        bytes32 salt = keccak256(abi.encode("hi"));

        L1ArbitrumTimelock l1Timelock = deployAndInit();
        InboxMock inbox = InboxMock(l1Timelock.inbox());
        scheduleAndRoll(l1Timelock, address(inbox), val, data, salt);

        vm.fee(21 gwei);
        uint256 submissionFee = inbox.calculateRetryableSubmissionFee(rData.data.length, 0);

        // set up the sender
        address payable sender = payable(address(678));
        uint256 extra = 150;
        sender.transfer(
            submissionFee + rData.l2Value + (rData.maxFeePerGas * rData.gasLimit) + extra
        );

        vm.expectRevert();
        vm.prank(sender);
        l1Timelock.execute{
            value: submissionFee + rData.l2Value + (rData.maxFeePerGas * rData.gasLimit) - 1
        }(address(inbox), val, data, 0, salt);
    }

    function testExecuteInboxInvalidData() external {
        Setter setter = new Setter();
        RetryableData memory rData = RetryableData({
            l2Target: address(235),
            l2Value: 10,
            excessFeeRefundAddress: address(236),
            callValueRefundAddress: address(237),
            gasLimit: 300_000,
            maxFeePerGas: 9 gwei,
            data: abi.encodeWithSelector(setter.setValue.selector, 10)
        });
        uint256 val = 105;
        bytes memory data = abi.encode(
            rData.l2Target,
            rData.l2Value,
            rData.excessFeeRefundAddress,
            rData.callValueRefundAddress,
            rData.gasLimit,
            rData.maxFeePerGas
        );
        // rData.data //  - make the data invalid

        bytes32 salt = keccak256(abi.encode("hi"));

        L1ArbitrumTimelock l1Timelock = deployAndInit();
        InboxMock inbox = InboxMock(l1Timelock.inbox());
        scheduleAndRoll(l1Timelock, address(inbox), val, data, salt);

        vm.fee(21 gwei);
        uint256 submissionFee = inbox.calculateRetryableSubmissionFee(rData.data.length, 0);

        // set up the sender
        address payable sender = payable(address(678));
        uint256 extra = 150;
        sender.transfer(
            submissionFee + rData.l2Value + (rData.maxFeePerGas * rData.gasLimit) + extra
        );

        vm.expectRevert();
        vm.prank(sender);
        l1Timelock.execute{
            value: submissionFee + rData.l2Value + (rData.maxFeePerGas * rData.gasLimit) + extra
        }(address(inbox), val, data, 0, salt);
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

    function roleError(address account, bytes32 role) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(uint160(account), 20),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(role), 32)
            )
        );
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
}
