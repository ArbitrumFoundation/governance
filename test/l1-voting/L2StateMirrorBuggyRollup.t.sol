// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {L2StateMirror} from "../../src/l1-voting/L2StateMirror.sol";
import {AssertionNode, AssertionStatus} from "@arbitrum/nitro-contracts/src/rollup/Assertion.sol";

/// @dev Rollup mock with a configurable failure mode per function.
contract BuggyRollup {
    enum Mode {
        Normal,
        Revert,
        RevertBomb,
        Empty,
        Short,
        Bomb,
        BurnGas,
        GarbageStatus,
        DirtyFields,
        ExtraReturn
    }

    bytes32 public confirmedHash;
    Mode public latestMode;
    Mode public assertionMode;

    constructor(bytes32 _confirmedHash) {
        confirmedHash = _confirmedHash;
    }

    function setConfirmedHash(bytes32 _confirmedHash) external {
        confirmedHash = _confirmedHash;
    }

    function setLatestMode(Mode m) external {
        latestMode = m;
    }

    function setAssertionMode(Mode m) external {
        assertionMode = m;
    }

    function latestConfirmed() external view returns (bytes32) {
        bytes32 hash = confirmedHash;
        if (latestMode == Mode.ExtraReturn) {
            // valid hash in the first word followed by junk
            assembly {
                mstore(0x00, hash)
                mstore(0x20, not(0))
                return(0x00, 0x40)
            }
        }
        _misbehave(latestMode, hash);
        return hash;
    }

    function getAssertion(bytes32 hash) external view returns (AssertionNode memory node) {
        if (assertionMode == Mode.GarbageStatus) {
            // 6 words with a status word that is not a valid AssertionStatus
            assembly {
                mstore(0x80, not(0))
                return(0x00, 0xc0)
            }
        }
        if (assertionMode == Mode.DirtyFields) {
            // exactly sized response with status Confirmed but every other word dirty
            assembly {
                mstore(0x00, not(0))
                mstore(0x20, not(0))
                mstore(0x40, not(0))
                mstore(0x60, not(0))
                mstore(0x80, 2) // AssertionStatus.Confirmed
                mstore(0xa0, not(0))
                return(0x00, 0xc0)
            }
        }
        if (assertionMode == Mode.ExtraReturn) {
            // an otherwise valid Confirmed node with a 7th junk word
            assembly {
                mstore(0x80, 2) // AssertionStatus.Confirmed
                mstore(0xc0, not(0))
                return(0x00, 0xe0)
            }
        }
        _misbehave(assertionMode, 0);
        if (hash == confirmedHash) {
            node.status = AssertionStatus.Confirmed;
        }
    }

    function _misbehave(Mode m, bytes32 word0) private view {
        if (m == Mode.Revert) {
            revert("rollup broken");
        }
        if (m == Mode.Empty) {
            assembly {
                return(0x00, 0)
            }
        }
        if (m == Mode.Short) {
            assembly {
                return(0x00, 8)
            }
        }
        if (m == Mode.BurnGas) {
            assembly {
                for {} 1 {} {}
            }
        }
        if (m == Mode.Bomb || m == Mode.RevertBomb) {
            // expand memory until nearly out of gas, then return/revert it all (a bomb sized
            // to the forwarded gas); the first word carries word0 so a capped 32 byte read
            // still sees a usable value
            uint256 doRevert = m == Mode.RevertBomb ? 1 : 0;
            assembly {
                mstore(0x00, word0)
                let size := 0x20
                for {} gt(gas(), 10000) {} {
                    mstore(size, not(0))
                    size := add(size, 0x20)
                }
                if doRevert { revert(0x00, size) }
                return(0x00, size)
            }
        }
    }
}

/// @notice Runs checkpointAssertion against a matrix of buggy rollup behaviors. The mirror must
///         use the live value only when the response is exactly the expected shape, falling
///         back to the cached assertion otherwise; a buggy rollup must never poison the cache
///         or brick checkpointing.
contract L2StateMirrorBuggyRollupTest is Test {
    bytes32 constant GOOD = keccak256("good");
    bytes32 constant NEXT = keccak256("next");

    BuggyRollup rollup;
    L2StateMirror mirror;

    function setUp() public {
        rollup = new BuggyRollup(GOOD);
        mirror = new L2StateMirror(address(1), address(2), 0, 0, address(3), 0, address(rollup));
        mirror.checkpointAssertion(); // cache GOOD
        vm.roll(block.number + 1);
    }

    /// @dev checkpointAssertion must succeed, commit the cached assertion, and leave the cache clean
    function _assertFallsBack() internal {
        mirror.checkpointAssertion();
        assertEq(mirror.getAssertionHashAt(block.number), GOOD);
        assertEq(mirror.lastSeenLatestConfirmedAssertion(), GOOD);
    }

    /// @dev checkpointAssertion must commit the live NEXT assertion despite the buggy encoding
    function _assertUsesLive() internal {
        mirror.checkpointAssertion();
        assertEq(mirror.getAssertionHashAt(block.number), NEXT);
        assertEq(mirror.lastSeenLatestConfirmedAssertion(), NEXT);
    }

    // --- latestConfirmed() misbehaving ---

    function testLatestConfirmedRevertBomb() public {
        rollup.setLatestMode(BuggyRollup.Mode.RevertBomb);
        _assertFallsBack();
    }

    function testLatestConfirmedEmptyReturndata() public {
        // also what a staticcall to a code-less (destroyed) rollup returns
        rollup.setLatestMode(BuggyRollup.Mode.Empty);
        _assertFallsBack();
    }

    function testLatestConfirmedShortReturndata() public {
        rollup.setLatestMode(BuggyRollup.Mode.Short);
        _assertFallsBack();
    }

    function testLatestConfirmedBurnsAllGas() public {
        rollup.setLatestMode(BuggyRollup.Mode.BurnGas);
        _assertFallsBack();
    }

    function testLatestConfirmedReturnBomb() public {
        // the capped copy defuses the bomb, and the oversized response is rejected even
        // though its first word holds a valid confirmed hash
        rollup.setConfirmedHash(NEXT);
        rollup.setLatestMode(BuggyRollup.Mode.Bomb);
        _assertFallsBack();
    }

    function testLatestConfirmedExtraReturndata() public {
        // a valid hash followed by junk is rejected: only exactly sized responses are used
        rollup.setConfirmedHash(NEXT);
        rollup.setLatestMode(BuggyRollup.Mode.ExtraReturn);
        _assertFallsBack();
    }

    // --- getAssertion() misbehaving ---

    function testGetAssertionReverts() public {
        rollup.setAssertionMode(BuggyRollup.Mode.Revert);
        _assertFallsBack();
    }

    function testGetAssertionEmptyReturndata() public {
        rollup.setAssertionMode(BuggyRollup.Mode.Empty);
        _assertFallsBack();
    }

    function testGetAssertionShortReturndata() public {
        rollup.setAssertionMode(BuggyRollup.Mode.Short);
        _assertFallsBack();
    }

    function testGetAssertionBurnsAllGas() public {
        rollup.setAssertionMode(BuggyRollup.Mode.BurnGas);
        _assertFallsBack();
    }

    function testGetAssertionReturnBomb() public {
        rollup.setAssertionMode(BuggyRollup.Mode.Bomb);
        _assertFallsBack();
    }

    function testGetAssertionGarbageStatus() public {
        // the status word is not a valid AssertionStatus; must fall back, not revert
        rollup.setAssertionMode(BuggyRollup.Mode.GarbageStatus);
        _assertFallsBack();
    }

    function testGetAssertionDirtyUnrelatedFields() public {
        // exactly sized response with status Confirmed; dirty sibling fields must not matter
        rollup.setConfirmedHash(NEXT);
        rollup.setAssertionMode(BuggyRollup.Mode.DirtyFields);
        _assertUsesLive();
    }

    function testGetAssertionExtraReturndata() public {
        // an otherwise valid Confirmed node with trailing junk is rejected
        rollup.setConfirmedHash(NEXT);
        rollup.setAssertionMode(BuggyRollup.Mode.ExtraReturn);
        _assertFallsBack();
    }

    // --- recovery ---

    function testCheckpointRecoversWhenRollupHeals() public {
        rollup.setLatestMode(BuggyRollup.Mode.Revert);
        _assertFallsBack();

        vm.roll(block.number + 1);
        rollup.setLatestMode(BuggyRollup.Mode.Normal);
        rollup.setConfirmedHash(NEXT);
        _assertUsesLive();
    }
}
