// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";

// Interfaces
interface IArbOwner {
    function setParentGasFloorPerToken(uint64 floorPerToken) external;
    function addChainOwner(address newOwner) external;
}

interface IArbSys {
    function arbOSVersion() external view returns (uint256);
}

/// @notice Settings to be applied on Arbitrum One are Arbitrum Nova after the ArbOS 50 upgrade
///         These settings include:
///         - Setting the new gas floor per token
///         - Adding the ResourceConstraintManager as a chain owner
/// @dev    Identical copies of this contract will be deployed on Arbitrum One and Arbitrum Nova
/// @dev    This contract is to be used after the chain has been successfully upgraded to ArbOS 50,
///         otherwise the call to setParentGasFloorPerToken will fail and the transaction will revert.
contract ArbOS50SettingsAction {
    uint64 public constant NEW_FLOOR_PER_TOKEN = 10;
    address public immutable resourceConstraintManagerAddress;

    // Precompile addresses
    address public constant ARB_OWNER_ADDRESS = 0x0000000000000000000000000000000000000070;
    address public constant ARBSYS_ADDRESS = 0x0000000000000000000000000000000000000064;

    constructor(address _resourceConstraintManagerAddress) {
        require(
            Address.isContract(address(_resourceConstraintManagerAddress)),
            "ArbOS50SettingsAction: _resourceConstraintManagerAddress is not a contract"
        );
        resourceConstraintManagerAddress = _resourceConstraintManagerAddress;
    }

    /// @notice Gets the current ArbOS version
    /// @dev    The ArbOS version returned by ArbSys includes an offset of 55
    ///         (https://github.com/OffchainLabs/nitro/blob/v3.8.0/precompiles/ArbSys.go#L65-L69)
    function getArbOSVersion() public view returns (uint256) {
        IArbSys arbSys = IArbSys(ARBSYS_ADDRESS);
        return arbSys.arbOSVersion() - 55;
    }

    function perform() public {
        // Verify that the chain is running ArbOS 50
        require(getArbOSVersion() >= 50, "ArbOS50SettingsAction: ArbOS version is less than 50");

        // Create ArbOwner precompile interface
        IArbOwner arbOwner = IArbOwner(ARB_OWNER_ADDRESS);

        // Set the new gas floor per token
        arbOwner.setParentGasFloorPerToken(NEW_FLOOR_PER_TOKEN);

        // Add the ResourceConstraintManager as a chain owner
        arbOwner.addChainOwner(resourceConstraintManagerAddress);
    }
}
