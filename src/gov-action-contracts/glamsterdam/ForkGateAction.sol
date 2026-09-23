// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

/// @notice Reverts unless the SLOTNUM opcode (EIP-7843) is available.
contract GlamsterdamForkGateAction {
    address public immutable probe;

    error ForkNotActive();

    constructor() {
        // Deploy runtime SLOTNUM; POP; STOP (0x4b5000), which solc 0.8.16 cannot emit directly.
        // Initcode (instruction bytes -> operation):
        //   62 4b5000  PUSH3 0x4b5000 - push the three runtime bytes as a word.
        //   60 00      PUSH1 0x00     - push the memory offset for MSTORE.
        //   52         MSTORE         - store the word at 0x00; runtime occupies 0x1d..0x1f.
        //   60 03      PUSH1 0x03     - push the runtime length (3 bytes).
        //   60 1d      PUSH1 0x1d     - push the runtime's starting memory offset (29).
        //   f3         RETURN         - return those 3 bytes as the deployed contract's code.
        // Runtime: 4b = SLOTNUM (push slot number), 50 = POP (discard it), 00 = STOP (succeed).
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
        // Forward only 5,000 gas to limit how much a failed probe burns.
        (bool forkIsActive,) = probe.staticcall{gas: 5000}("");
        if (!forkIsActive) revert ForkNotActive();
    }
}
