// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

/// @notice increments an integer without checking for overflows
/// @dev from https://github.com/ethereum/solidity/issues/11721#issuecomment-890917517
function uncheckedInc(uint256 x) pure returns (uint256) {
    unchecked {
        return x + 1;
    }
}

/// @title A token contract with governance capabilities
interface IERC20VotesUpgradeable is
    IVotesUpgradeable,
    IERC20Upgradeable,
    IERC20PermitUpgradeable
{}

/// @notice Retreives the selector from function calldata
function getSelector(bytes memory calldataWithSelector) pure returns (bytes4) {
    uint256 firstWord;
    assembly {
        firstWord := mload(add(calldataWithSelector, 0x20))
    }
    return bytes4(uint32(firstWord >> 224));
}

// h/t https://ethereum.stackexchange.com/a/131291
/// @notice Creates new bytes memory with the selector removed from function calldata
function removeSelector(bytes memory calldataWithSelector) pure returns (bytes memory) {
    bytes memory calldataWithoutSelector;

    require(calldataWithSelector.length >= 4);

    assembly {
        let totalLength := mload(calldataWithSelector)
        let targetLength := sub(totalLength, 4)
        calldataWithoutSelector := mload(0x40)
        
        // Set the length of callDataWithoutSelector (initial length - 4)
        mstore(calldataWithoutSelector, targetLength)

        // Mark the memory space taken for callDataWithoutSelector as allocated
        mstore(0x40, add(calldataWithoutSelector, add(0x20, targetLength)))

        // Process first 32 bytes (we only take the last 28 bytes)
        mstore(add(calldataWithoutSelector, 0x20), shl(0x20, mload(add(calldataWithSelector, 0x20))))

        // Process all other data by chunks of 32 bytes
        for { let i := 0x1C } lt(i, targetLength) { i := add(i, 0x20) } {
            mstore(add(add(calldataWithoutSelector, 0x20), i), mload(add(add(calldataWithSelector, 0x20), add(i, 0x04))))
        }
    }

    return calldataWithoutSelector;
}