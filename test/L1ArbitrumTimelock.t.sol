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

contract L1ArbitrumTimelockTest is Test {
    address inbox = address(137);
    address bridge = address(138);
    uint256 minDelay = 10;
    address l2Timelock = address(139);
    address outbox = address(140);

    function deploy() internal returns (L1ArbitrumTimelock) {
        L1ArbitrumTimelock timelock =
            L1ArbitrumTimelock(payable(TestUtil.deployProxy(address(new L1ArbitrumTimelock()))));

        return timelock;
    }

    function deployAndInit() internal returns (L1ArbitrumTimelock) {
        L1ArbitrumTimelock l1Timelock = deploy();
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        vm.mockCall(inbox, bytes.concat(IInbox(inbox).bridge.selector), abi.encode(bridge));
        l1Timelock.initialize(minDelay, new address[](0), executors, inbox, l2Timelock);

        return l1Timelock;
    }

    function testDoesDeploy() external {
        L1ArbitrumTimelock l1Timelock = deployAndInit();

        assertEq(l1Timelock.inbox(), inbox, "inbox");
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
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        vm.mockCall(inbox, bytes.concat(IInbox(inbox).bridge.selector), abi.encode(bridge));
        vm.expectRevert("L1ArbitrumTimelock: zero inbox");
        l1Timelock.initialize(minDelay, new address[](0), executors, address(0), l2Timelock);
    }

    function testDoesNotDeployZeroL2Timelock() external {
        L1ArbitrumTimelock l1Timelock = deploy();
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        vm.mockCall(inbox, bytes.concat(IInbox(inbox).bridge.selector), abi.encode(bridge));
        vm.expectRevert("L1ArbitrumTimelock: zero l2 timelock");
        l1Timelock.initialize(minDelay, new address[](0), executors, inbox, address(0));
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

    function dummyScheduleArgs() internal returns (ScheduleArgs memory) {
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

    function deployAndScheduleAndRoll(
        address target,
        uint256 value,
        bytes memory payload,
        bytes32 salt
    ) internal returns (L1ArbitrumTimelock) {
        L1ArbitrumTimelock l1Timelock = deployAndInit();

        mockActiveOutbox(outbox, l2Timelock);
        vm.prank(bridge);
        l1Timelock.schedule(target, value, payload, 0, salt, minDelay);

        vm.warp(block.timestamp + minDelay);

        return l1Timelock;
    }

    function testExecute() internal {
        // L1ArbitrumTimelock l1Timelock = deployAndScheduleAndRoll();
        // Setter setter = new Setter();
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

    function roleError(address account, bytes32 role) internal returns (string memory) {
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
        vm.expectRevert(bytes(roleError(address(this), l1Timelock.PROPOSER_ROLE())));
        l1Timelock.schedule(
            sarg.target, sarg.value, sarg.payload, sarg.predecessor, sarg.salt, minDelay
        );

        vm.expectRevert(bytes(roleError(address(this), l1Timelock.PROPOSER_ROLE())));
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
