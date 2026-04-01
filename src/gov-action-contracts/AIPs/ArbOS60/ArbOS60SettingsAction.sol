// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";

// Interfaces
interface IArbOwner {
    function addChainOwner(address newOwner) external;
    function removeChainOwner(address ownerToRemove) external;
}

interface IArbSys {
    function arbOSVersion() external view returns (uint256);
}

/// @notice Settings to be applied on Arbitrum One and Arbitrum Nova after the ArbOS 60 upgrade
///         These settings include:
///         - Adding the ResourceConstraintManager (v2) as a chain owner
///         - Adding the BaseConstraintManager as a chain owner
///         - Removing the previous ResourceConstraintManager (v1) as a chain owner
/// @dev    Identical copies of this contract will be deployed on Arbitrum One and Arbitrum Nova
/// @dev    This contract is to be used after the chain has been successfully upgraded to ArbOS 60.
contract ArbOS60SettingsAction {
    address public immutable newResourceConstraintManagerAddress;
    address public immutable baseConstraintManagerAddress;
    address public immutable oldResourceConstraintManagerAddress;

    // Precompile addresses
    address public constant ARB_OWNER_ADDRESS = 0x0000000000000000000000000000000000000070;
    address public constant ARBSYS_ADDRESS = 0x0000000000000000000000000000000000000064;

    constructor(
        address _newResourceConstraintManagerAddress,
        address _baseConstraintManagerAddress,
        address _oldResourceConstraintManagerAddress
    ) {
        require(
            Address.isContract(_newResourceConstraintManagerAddress),
            "ArbOS60SettingsAction: _newResourceConstraintManagerAddress is not a contract"
        );
        require(
            Address.isContract(_baseConstraintManagerAddress),
            "ArbOS60SettingsAction: _baseConstraintManagerAddress is not a contract"
        );
        require(
            Address.isContract(_oldResourceConstraintManagerAddress),
            "ArbOS60SettingsAction: _oldResourceConstraintManagerAddress is not a contract"
        );

        newResourceConstraintManagerAddress = _newResourceConstraintManagerAddress;
        baseConstraintManagerAddress = _baseConstraintManagerAddress;
        oldResourceConstraintManagerAddress = _oldResourceConstraintManagerAddress;
    }

    /// @notice Gets the current ArbOS version
    /// @dev    The ArbOS version returned by ArbSys includes an offset of 55
    ///         (https://github.com/OffchainLabs/nitro/blob/v3.8.0/precompiles/ArbSys.go#L65-L69)
    function getArbOSVersion() public view returns (uint256) {
        IArbSys arbSys = IArbSys(ARBSYS_ADDRESS);
        return arbSys.arbOSVersion() - 55;
    }

    function perform() public {
        // Verify that the chain is running ArbOS 60
        require(getArbOSVersion() >= 60, "ArbOS60SettingsAction: ArbOS version is less than 60");

        // Create ArbOwner precompile interface
        IArbOwner arbOwner = IArbOwner(ARB_OWNER_ADDRESS);

        // Add the new ResourceConstraintManager (v2) and the BaseConstraintManager as chain owners
        arbOwner.addChainOwner(newResourceConstraintManagerAddress);
        arbOwner.addChainOwner(baseConstraintManagerAddress);

        // Remove the previous ResourceConstraintManager (v1) as a chain owner
        arbOwner.removeChainOwner(oldResourceConstraintManagerAddress);
    }
}
