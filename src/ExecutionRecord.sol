// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./KeyValueStore.sol";

contract ExecutionRecord {
    KeyValueStore public immutable store;
    bytes32 public immutable actionContractId;

    error ActionAlreadyExecuted(uint256 actionId);

    constructor(KeyValueStore _store, string memory _uniqueActionName) {
        store = _store;
        actionContractId = keccak256(bytes(_uniqueActionName));
    }

    function _set(uint256 key, uint256 value) internal {
        store.set(computeKey(key), value);
    }

    function _get(uint256 key) internal view returns (uint256) {
        return store.get(computeKey(key));
    }

    function computeKey(uint256 key) public view returns (uint256) {
        return uint256(keccak256(abi.encode(actionContractId, key)));
    }
}
