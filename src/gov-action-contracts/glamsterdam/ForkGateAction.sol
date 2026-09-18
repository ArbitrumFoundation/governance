// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

/// @notice Action that reverts unless the host chain has forked, detected by probing for an opcode
///         that the fork introduces. Should be included as a host-chain action in proposal data,
///         alongside the actions it is gating.
///
///         The L1 timelock executes every action in a proposal in a single `executeBatch` call, and
///         that includes creating the retryable tickets that carry actions to other chains. So a
///         revert here reverts the whole batch, including ticket creation, and therefore gates
///         actions on other chains as well as on the host chain.
///
///         OpenZeppelin's TimelockController marks an operation done only after every call in the
///         batch has succeeded, and operations never expire. A batch that reverts here therefore
///         stays in the `Ready` state and can simply be executed again once the fork has landed.
///         This is the same mechanism OfficeHoursAction relies on.
contract OpcodeForkGateAction {
    /// @notice Contract whose runtime code contains an opcode introduced by the fork. Calling it
    ///         fails before the fork and succeeds after it.
    address public immutable probe;
    /// @notice Gas forwarded to the probe. Before the fork the probe hits an undefined opcode,
    ///         which consumes everything forwarded to it, so this bounds the gas burned by a failed
    ///         check. It must still be comfortably more than the probe costs after the fork.
    uint256 public immutable probeGas;
    /// @notice Optional lower bound on execution time, as a backstop against a misconfigured probe.
    ///         Set to 0 to rely on the probe alone.
    uint256 public immutable notBeforeTimestamp;

    error ProbeHasNoCode();
    error TooEarly(uint256 currentTimestamp, uint256 notBeforeTimestamp);
    error ForkNotActive();

    constructor(address _probe, uint256 _probeGas, uint256 _notBeforeTimestamp) {
        // An address with no code accepts any call and returns success, which would make the gate
        // pass unconditionally. Refuse to deploy against one.
        if (_probe.code.length == 0) revert ProbeHasNoCode();
        probe = _probe;
        probeGas = _probeGas;
        notBeforeTimestamp = _notBeforeTimestamp;
    }

    function perform() external view {
        if (block.timestamp < notBeforeTimestamp) {
            revert TooEarly(block.timestamp, notBeforeTimestamp);
        }
        (bool forkIsActive,) = probe.staticcall{gas: probeGas}("");
        if (!forkIsActive) revert ForkNotActive();
    }
}

/// @notice Gates a proposal on Glamsterdam being live on Ethereum, by probing for SLOTNUM
///         (EIP-7843, opcode 0x4b).
/// @dev    EIP-7843 is scheduled for inclusion in Glamsterdam but the EIP list is not frozen. Before
///         deploying, re-check EIP-7773 to confirm SLOTNUM is still in. If it is dropped, deploy a
///         probe for a different fork-introduced opcode instead and point this at that address; the
///         gate itself needs no change.
contract GlamsterdamForkGateAction is OpcodeForkGateAction {
    constructor()
        OpcodeForkGateAction(
            // TODO: address of the deployed SlotNumProbe on Ethereum mainnet. Until this is filled
            // in the contract cannot be deployed, since the constructor rejects a codeless probe.
            address(0),
            5000, // probeGas: SLOTNUM costs 2 post-fork; this bounds the pre-fork burn
            0 // notBeforeTimestamp: rely on the probe. Glamsterdam has no announced mainnet
            // activation time, which is why this gate exists rather than a timestamp check.
        )
    {}
}
