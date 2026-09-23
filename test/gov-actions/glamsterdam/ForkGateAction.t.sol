// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../../src/gov-action-contracts/glamsterdam/ForkGateAction.sol";

/// @notice Run under both --evm-version osaka and --evm-version amsterdam.
contract ForkGateActionTest is Test {
    GlamsterdamForkGateAction gate;
    address probe;

    function setUp() public {
        gate = new GlamsterdamForkGateAction();
        probe = gate.probe();
    }

    function test_constructorDeploysProbe() public {
        assertEq(probe.code, hex"4b5000", "probe runtime");
    }

    function test_gateFollowsTheProbe() public {
        (bool slotNumIsAvailable,) = probe.staticcall{gas: 5000}("");
        if (slotNumIsAvailable) {
            gate.perform();
        } else {
            vm.expectRevert(GlamsterdamForkGateAction.ForkNotActive.selector);
            gate.perform();
        }
    }

    /// @notice The bytecode override used to simulate the post-fork path.
    function test_gatePassesWhenProbeSucceeds() public {
        vm.etch(probe, hex"00");
        gate.perform();
    }

    function test_gateRevertsWhenProbeFails() public {
        vm.etch(probe, hex"fe");
        vm.expectRevert(GlamsterdamForkGateAction.ForkNotActive.selector);
        gate.perform();
    }

    function test_failingProbeBurnsBoundedGas() public {
        vm.etch(probe, hex"fe");

        uint256 before = gasleft();
        try gate.perform() {
            revert("expected revert");
        } catch {}
        uint256 used = before - gasleft();

        // 5,000 gas for the probe plus call overhead and the outer try/catch.
        assertLt(used, 25_000, "gas burned by a failed check");
    }

    function test_worksUnderDelegatecall() public {
        DelegateCaller caller = new DelegateCaller();
        vm.etch(probe, hex"00");
        caller.performVia(address(gate));

        vm.etch(probe, hex"fe");
        vm.expectRevert(GlamsterdamForkGateAction.ForkNotActive.selector);
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
