// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./KeyValueStore.sol";

/// @notice Stores a record that the action executed.
///         Can be useful for enforcing dependency between actions
/// @dev    This contract is designed to be inherited by action contracts, so it
///         it must not use any local storage
contract ActionExecutionRecord {
    /// @notice The key value store used to record the execution
    /// @dev    Local storage cannot be used in action contracts as they're delegate called into
    KeyValueStore public immutable store;

    /// @notice A unique id for this action contract
    bytes32 public immutable actionContractId;

    constructor(KeyValueStore _store, string memory _uniqueActionName) {
        store = _store;
        actionContractId = keccak256(bytes(_uniqueActionName));
    }

    /// @notice Sets a value in the store
    /// @dev    Combines the provided key with the action contract id
    function _set(uint256 key, uint256 value) internal {
        store.set(computeKey(key), value);
    }

    /// @notice Gets a value from the store
    /// @dev    Combines the provided key with the action contract id
    function _get(uint256 key) internal view returns (uint256) {
        return store.get(computeKey(key));
    }

    /// @notice This contract uses a composite key of the provided key and the action contract id.
    ///         This function can be used to calculate the composite key
    function computeKey(uint256 key) public view returns (uint256) {
        return uint256(keccak256(abi.encode(actionContractId, key)));
    }
}
