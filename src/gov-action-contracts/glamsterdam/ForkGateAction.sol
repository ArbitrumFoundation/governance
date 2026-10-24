// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

/// @notice Reverts unless the SLOTNUM opcode (EIP-7843) is available.
contract GlamsterdamForkGateAction {
    address public immutable probe;

    error ForkNotActive();

    constructor() {
        // Deploy runtime SLOTNUM; STOP (0x4b00), which solc 0.8.16 cannot emit directly.
        // Initcode (instruction bytes -> operation):
        //   61 4b00  PUSH2 0x4b00 - push the two runtime bytes as a word.
        //   60 00    PUSH1 0x00   - push the memory offset for MSTORE.
        //   52       MSTORE       - store the word at 0x00; runtime occupies 0x1e..0x1f.
        //   60 02    PUSH1 0x02   - push the runtime length (2 bytes).
        //   60 1e    PUSH1 0x1e   - push the runtime's starting memory offset (30).
        //   f3       RETURN       - return those 2 bytes as the deployed contract's code.
        // Runtime: 4b = SLOTNUM (push slot number), 00 = STOP (succeed).
        bytes memory initcode = hex"614b006000526002601ef3";
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
