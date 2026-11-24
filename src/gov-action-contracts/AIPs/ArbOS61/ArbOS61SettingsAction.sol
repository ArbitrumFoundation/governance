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

/// @notice Settings to be applied on Arbitrum One and Arbitrum Nova after the ArbOS 61 upgrade
///         These settings include:
///         - Adding the BaseFeeManager as a chain owner
/// @dev    Identical copies of this contract will be deployed on Arbitrum One and Arbitrum Nova
/// @dev    This contract is to be used after the chain has been successfully upgraded to ArbOS 61.
contract ArbOS61SettingsAction {
    address public immutable baseFeeManagerAddress;

    // Precompile addresses
    address public constant ARB_OWNER_ADDRESS = 0x0000000000000000000000000000000000000070;
    address public constant ARBSYS_ADDRESS = 0x0000000000000000000000000000000000000064;

    constructor(
        address _baseFeeManagerAddress
    ) {
        require(
            Address.isContract(_baseFeeManagerAddress),
            "ArbOS61SettingsAction: _baseFeeManagerAddress is not a contract"
        );
        
        baseFeeManagerAddress = _baseFeeManagerAddress;
    }

    /// @notice Gets the current ArbOS version
    /// @dev    The ArbOS version returned by ArbSys includes an offset of 55
    ///         (https://github.com/OffchainLabs/nitro/blob/v3.8.0/precompiles/ArbSys.go#L65-L69)
    function getArbOSVersion() public view returns (uint256) {
        IArbSys arbSys = IArbSys(ARBSYS_ADDRESS);
        return arbSys.arbOSVersion() - 55;
    }

    function perform() public {
        // Verify that the chain is running ArbOS 61
        require(getArbOSVersion() >= 61, "ArbOS61SettingsAction: ArbOS version is less than 61");

        // Create ArbOwner precompile interface
        IArbOwner arbOwner = IArbOwner(ARB_OWNER_ADDRESS);

        // Add the BaseFeeManager as a chain owner
        arbOwner.addChainOwner(baseFeeManagerAddress);
    }
}
