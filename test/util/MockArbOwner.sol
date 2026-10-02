// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

/// @notice Mocks of the ArbOwner, ArbOwnerPublic and ArbGasInfo precompiles, for etching over the
///         precompile addresses in tests.
///
/// @dev    Arbitrum precompiles are implemented inside nitro, not as EVM contracts: on chain their
///         bytecode is the single byte 0xfe (INVALID). Any EVM that does not special case them,
///         forge's included, reverts on a call to one. So a test of an action that touches a
///         precompile has to etch a mock over the address first, the same way E2E.t.sol etches
///         ArbSysMock over address(100).
///
///         ArbOwnerMock holds the state. The other two are read-only views onto it, so that setting
///         a value through ArbOwner at 0x70 is observable through ArbOwnerPublic at 0x6b and
///         ArbGasInfo at 0x6c, as it is on a real chain. Etching the same code at all three
///         addresses would not work, since each address gets its own storage.
interface IArbOwnerMockState {
    function parentGasFloorPerToken() external view returns (uint64);
    function perBatchGasCharge() external view returns (int64);
}

address constant ARB_OWNER = 0x0000000000000000000000000000000000000070;

contract ArbOwnerMock {
    uint64 public parentGasFloorPerToken;
    int64 public perBatchGasCharge;

    function setParentGasFloorPerToken(uint64 floorPerToken) external {
        parentGasFloorPerToken = floorPerToken;
    }

    function setPerBatchGasCharge(int64 cost) external {
        perBatchGasCharge = cost;
    }
}

contract ArbOwnerPublicMock {
    function getParentGasFloorPerToken() external view returns (uint64) {
        return IArbOwnerMockState(ARB_OWNER).parentGasFloorPerToken();
    }
}

contract ArbGasInfoMock {
    function getPerBatchGasCharge() external view returns (int64) {
        return IArbOwnerMockState(ARB_OWNER).perBatchGasCharge();
    }
}

/// @notice An ArbOwner whose setters silently do nothing, to check that an action's post-state
///         assertions actually fire rather than being decorative.
contract ArbOwnerMockThatIgnoresWrites {
    uint64 public parentGasFloorPerToken;
    int64 public perBatchGasCharge;

    function setParentGasFloorPerToken(uint64) external {}
    function setPerBatchGasCharge(int64) external {}
}
