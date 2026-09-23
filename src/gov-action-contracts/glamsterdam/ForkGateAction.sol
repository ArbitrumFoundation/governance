// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

/// @notice Reverts unless the SLOTNUM opcode (EIP-7843) is available.
contract GlamsterdamForkGateAction {
    address public immutable probe;

    error ForkNotActive();

    constructor() {
        // Deploy runtime SLOTNUM; POP; STOP (0x4b5000), which solc 0.8.16 cannot emit directly.
        bytes memory initcode = hex"624b50006000526003601df3";
        address deployedProbe;
        assembly {
            deployedProbe := create(0, add(initcode, 0x20), mload(initcode))
        }
        require(deployedProbe != address(0), "GlamsterdamForkGateAction: probe deployment failed");
        probe = deployedProbe;
    }

    function perform() external view {
        // An undefined opcode consumes all forwarded gas before the fork.
        (bool forkIsActive,) = probe.staticcall{gas: 5000}("");
        if (!forkIsActive) revert ForkNotActive();
    }
}
