// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

contract KeyValueStore {
    mapping(uint256 => uint256) public store;

    function set(uint256 key, uint256 value) external {
        store[computeKey(msg.sender, key)] = value;
    }

    function get(uint256 key) external view returns (uint256) {
        return _get(msg.sender, key);
    }

    function get(address owner, uint256 key) external view returns (uint256) {
        return _get(owner, key);
    }

    function computeKey(address owner, uint256 key) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(owner, key)));
    }

    function _get(address owner, uint256 key) internal view returns (uint256) {
        return store[computeKey(owner, key)];
    }
}
