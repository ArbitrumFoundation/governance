// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

/// @notice Helpers for the raw-bytecode probe contract used to detect whether the host chain has
///         forked to Glamsterdam.
///
///         The probe's runtime is three bytes: `SLOTNUM; POP; STOP`. SLOTNUM (0x4b) is introduced by
///         EIP-7843, which is scheduled for inclusion in Glamsterdam. Before the fork 0x4b is an
///         undefined opcode, so calling the probe consumes all forwarded gas and fails; after the
///         fork it pushes the slot number, which is popped and discarded, and the call succeeds
///         returning no data.
///
///         The probe is deployed as raw bytecode rather than emitted by solc because solc has no
///         way to emit an opcode it does not know about, and because keeping the probe to three
///         bytes makes it trivial to eyeball.
///
/// @dev    The probe MUST be deployed as a standalone contract and passed into
///         OpcodeForkGateAction's constructor, rather than being deployed by the gate itself. Its
///         address is then a single stable target that simulation tools can apply a bytecode
///         override to, which is the only way to demonstrate the post-fork path before the fork
///         lands. See README.md in this directory.
library SlotNumProbe {
    /// @notice Runtime code of the probe: SLOTNUM (0x4b); POP (0x50); STOP (0x00)
    bytes internal constant RUNTIME = hex"4b5000";

    /// @notice Initcode that deploys RUNTIME.
    /// @dev    PUSH3 0x4b5000 : 62 4b5000  (probe runtime, right aligned in the word)
    ///         PUSH1 0x00     : 60 00
    ///         MSTORE         : 52         (word at 0x00; runtime occupies bytes 0x1d..0x1f)
    ///         PUSH1 0x03     : 60 03      (return size)
    ///         PUSH1 0x1d     : 60 1d      (return offset)
    ///         RETURN         : f3
    bytes internal constant INITCODE = hex"624b50006000526003601df3";

    /// @notice Deploy the probe. Used by tests; for mainnet see README.md, which deploys through
    ///         the canonical CREATE2 factory so the address is known before the proposal is drafted.
    function deploy() internal returns (address probe) {
        bytes memory initcode = INITCODE;
        assembly {
            probe := create(0, add(initcode, 0x20), mload(initcode))
        }
        require(probe != address(0), "SlotNumProbe: deployment failed");
        require(keccak256(probe.code) == keccak256(RUNTIME), "SlotNumProbe: unexpected runtime");
    }
}
