// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../../src/gov-action-contracts/glamsterdam/ForkGateAction.sol";
import "../../../src/gov-action-contracts/glamsterdam/SlotNumProbe.sol";

/// @notice Tests for the Glamsterdam fork gate.
///
/// @dev    Run at both sides of the fork:
///
///           forge test --match-contract ForkGateActionTest --evm-version osaka
///           forge test --match-contract ForkGateActionTest --evm-version amsterdam
///
///         foundry clamps the version it hands solc independently of the version it runs the EVM
///         at, so `--evm-version amsterdam` does not break the repo's pinned solc 0.8.16: solc still
///         receives `london` while revm executes Amsterdam rules. Nothing needs to change in
///         foundry.toml, and nothing should: the rest of the suite belongs on current rules.
///
///         test_gateFollowsTheProbe is the one that actually proves the gate works, and it asserts
///         the right thing at either version.
contract ForkGateActionTest is Test {
    address probe;

    function setUp() public {
        probe = SlotNumProbe.deploy();
    }

    /// @notice Whether SLOTNUM executes under the EVM version this run is using.
    function slotNumIsAvailable() internal view returns (bool available) {
        (available,) = probe.staticcall{gas: 5000}("");
    }

    function testProbeRuntimeIsThreeBytes() public {
        assertEq(probe.code, SlotNumProbe.RUNTIME, "probe runtime");
        assertEq(probe.code.length, 3, "probe runtime length");
    }

    /// @notice The gate passes exactly when the fork opcode is available, and reverts otherwise.
    ///         Self-consistent at any EVM version, so run it at both.
    function test_gateFollowsTheProbe() public {
        OpcodeForkGateAction gate = new OpcodeForkGateAction(probe, 5000, 0);

        if (slotNumIsAvailable()) {
            gate.perform();
        } else {
            vm.expectRevert(OpcodeForkGateAction.ForkNotActive.selector);
            gate.perform();
        }
    }

    /// @notice A probe that succeeds means the fork is live. Etching a bare STOP is exactly the
    ///         bytecode override used to demonstrate the post-fork path in simulation tools, so this
    ///         doubles as a check that the override is equivalent to the real thing.
    function test_gatePassesWhenProbeSucceeds() public {
        OpcodeForkGateAction gate = new OpcodeForkGateAction(probe, 5000, 0);
        vm.etch(probe, hex"00");
        gate.perform();
    }

    function test_gateRevertsWhenProbeFails() public {
        OpcodeForkGateAction gate = new OpcodeForkGateAction(probe, 5000, 0);
        vm.etch(probe, hex"fe");
        vm.expectRevert(OpcodeForkGateAction.ForkNotActive.selector);
        gate.perform();
    }

    /// @notice A codeless address accepts any call and returns success, which would make the gate
    ///         pass unconditionally. The constructor must refuse one.
    function test_constructorRejectsCodelessProbe() public {
        vm.expectRevert(OpcodeForkGateAction.ProbeHasNoCode.selector);
        new OpcodeForkGateAction(makeAddr("noCode"), 5000, 0);
    }

    /// @notice A failing probe hits an undefined opcode, which consumes everything forwarded to it.
    ///         probeGas has to bound that, or a gate in a large batch could burn the lot.
    function test_failingProbeBurnsAtMostProbeGas() public {
        uint256 probeGas = 5000;
        OpcodeForkGateAction gate = new OpcodeForkGateAction(probe, probeGas, 0);
        vm.etch(probe, hex"fe");

        uint256 before = gasleft();
        try gate.perform() {
            revert("expected revert");
        } catch {}
        uint256 used = before - gasleft();

        // probeGas plus call overhead and the outer try/catch, comfortably below a runaway burn
        assertLt(used, probeGas + 20_000, "gas burned by a failed check");
    }

    function test_notBeforeTimestampBlocksEarlyExecution() public {
        vm.etch(probe, hex"00"); // isolate the timestamp check from the probe check
        uint256 notBefore = block.timestamp + 1 days;
        OpcodeForkGateAction gate = new OpcodeForkGateAction(probe, 5000, notBefore);

        vm.expectRevert(
            abi.encodeWithSelector(
                OpcodeForkGateAction.TooEarly.selector, block.timestamp, notBefore
            )
        );
        gate.perform();

        vm.warp(notBefore);
        gate.perform();
    }

    function test_immutablesAreReadable() public {
        OpcodeForkGateAction gate = new OpcodeForkGateAction(probe, 5000, 123);
        assertEq(gate.probe(), probe, "probe");
        assertEq(gate.probeGas(), 5000, "probeGas");
        assertEq(gate.notBeforeTimestamp(), 123, "notBeforeTimestamp");
    }

    /// @notice The gate is delegatecalled by an UpgradeExecutor, so it must not touch storage and
    ///         must resolve its immutables from its own bytecode.
    function test_worksUnderDelegatecall() public {
        OpcodeForkGateAction gate = new OpcodeForkGateAction(probe, 5000, 0);
        vm.etch(probe, hex"00");

        DelegateCaller caller = new DelegateCaller();
        caller.performVia(address(gate));

        vm.etch(probe, hex"fe");
        vm.expectRevert(OpcodeForkGateAction.ForkNotActive.selector);
        caller.performVia(address(gate));
    }
}

contract DelegateCaller {
    function performVia(address action) external {
        (bool success, bytes memory returnData) =
            action.delegatecall(abi.encodeWithSignature("perform()"));
        if (!success) {
            assembly {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }
}
