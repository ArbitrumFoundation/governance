// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {L2StateMirror} from "../../src/l1-voting/L2StateMirror.sol";
import {AssertionNode, AssertionStatus} from "@arbitrum/nitro-contracts/src/rollup/Assertion.sol";

/// @dev Healthy rollup that always returns correct data, but burns far more gas per call than the
///      real ~13-16k so the floor is tested against a conservative cost. Being `view` it can only
///      burn gas by hashing. If starved by the caller (EIP-150 63/64 rule) the loop runs out.
contract GasBurningRollup {
    bytes32 public confirmed;
    uint256 public immutable burn;

    constructor(bytes32 _confirmed, uint256 _burn) {
        confirmed = _confirmed;
        burn = _burn;
    }

    function _burnGas() internal view {
        uint256 start = gasleft();
        bytes32 h;
        while (start - gasleft() < burn) {
            h = keccak256(abi.encode(h));
        }
    }

    function latestConfirmed() external view returns (bytes32) {
        _burnGas();
        return confirmed;
    }

    function getAssertion(bytes32 hash) external view returns (AssertionNode memory node) {
        _burnGas();
        if (hash == confirmed) {
            node.status = AssertionStatus.Confirmed;
        }
    }
}

/// @dev Exposes _tryGetLatestConfirmedAssertion with no work after it. This is the worst case
///      caller for gas griefing: it can complete on the little gas a starved call leaves behind,
///      so if the floor holds here it holds for any caller that does more work.
contract L2StateMirrorHarness is L2StateMirror {
    constructor(address _rollup)
        L2StateMirror(address(1), address(2), 0, 0, address(3), 0, _rollup)
    {}

    function tryGetLatestConfirmedAssertion() external view returns (bytes32) {
        return _tryGetLatestConfirmedAssertion();
    }
}

/// @notice Demonstrates that the gas floor in _tryRollupCall defends against a gas-griefing
///         attack: without it a caller can pick a stipend that leaves the outer frame alive while
///         starving the rollup staticcall (EIP-150 forwards at most 63/64 of the gas left) so it
///         runs out, misreading a live rollup as unreachable - e.g. tricking checkpointAssertion
///         into committing the stale cached assertion. Comment out the
///         `if (gasleft() < ROLLUP_CALL_GAS_FLOOR) revert` in L2StateMirror to watch these fail.
///
///         Invariant: for ANY caller-chosen stipend the fetch either reverts or reports the live
///         assertion. It never reports 0 while the rollup is healthy.
contract L2StateMirrorGasTest is Test {
    bytes32 constant CONFIRMED = keccak256("confirmed");

    // each rollup call burns well above the real ~13-16k to prove the floor is conservative
    uint256 constant ROLLUP_GAS_BURN = 150_000;

    L2StateMirrorHarness mirror;

    function setUp() public {
        mirror =
            new L2StateMirrorHarness(address(new GasBurningRollup(CONFIRMED, ROLLUP_GAS_BURN)));
    }

    /// @dev Low-level probe so a revert/OOG is observable instead of bubbling up. Returns
    ///      whether the call completed and, if so, the assertion hash it reported.
    function _probe(uint256 gasStipend) internal view returns (bool ok, bytes32 reported) {
        (bool success, bytes memory ret) = address(mirror).staticcall{gas: gasStipend}(
            abi.encodeCall(L2StateMirrorHarness.tryGetLatestConfirmedAssertion, ())
        );
        ok = success && ret.length == 32;
        if (ok) {
            reported = abi.decode(ret, (bytes32));
        }
    }

    /// @dev Binary search the minimal stipend at which the call completes, then check what it
    ///      reports. That boundary is the adversarial sweet spot: the outer frame has just enough
    ///      gas to survive, so without the floor the rollup staticcall would have received less
    ///      than it needs and OOG'd, wrongly reporting 0 (unreachable). The floor must push this
    ///      boundary high enough that the rollup call always succeeds.
    function testGasGriefCannotForceUnreachable() public {
        // sanity: with ample gas the live rollup's assertion is reported
        (bool okAmple, bytes32 reportedAmple) = _probe(3_000_000);
        assertTrue(okAmple, "reverted with ample gas");
        assertEq(reportedAmple, CONFIRMED, "must report the live rollup's assertion");

        // `ok` is monotonic in gas: below the threshold the call reverts (floor trip, or the
        // frame runs out), at or above it the call completes.
        uint256 lo = 0; // reverts
        uint256 hi = 3_000_000; // completes
        while (hi - lo > 1) {
            uint256 mid = (lo + hi) / 2;
            (bool ok,) = _probe(mid);
            if (ok) {
                hi = mid;
            } else {
                lo = mid;
            }
        }

        (bool okMin, bytes32 reportedMin) = _probe(hi);
        assertTrue(okMin, "boundary stipend should not revert");
        assertEq(reportedMin, CONFIRMED, "gas-starved call misread a live rollup as unreachable");
        emit log_named_uint("minimal non-reverting gas stipend", hi);
    }

    /// @dev Sweep the whole starvation region: no stipend may complete while reporting 0.
    function testNoStipendReportsFalseZero() public {
        for (uint256 g = 0; g < 600_000; g += 997) {
            (bool ok, bytes32 reported) = _probe(g);
            if (ok) {
                assertEq(reported, CONFIRMED, "a starved call reported a false zero");
            }
        }
    }

    /// @dev Below the floor the failure is the explicit guard, not a blind out-of-gas.
    function testGasTooLowRevertsExplicitly() public {
        vm.expectRevert(L2StateMirror.GasTooLowForRollupCall.selector);
        mirror.tryGetLatestConfirmedAssertion{gas: 250_000}();
    }
}
