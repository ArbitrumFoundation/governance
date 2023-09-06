// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

abstract contract OpEnum {
    enum Operation {
        Call,
        DelegateCall
    }
}

interface IGnosisSafe {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function isOwner(address owner) external view returns (bool);
    function isModuleEnabled(address module) external view returns (bool);
    function addOwnerWithThreshold(address owner, uint256 threshold) external;
    function removeOwner(address prevOwner, address owner, uint256 threshold) external;
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        OpEnum.Operation operation
    ) external returns (bool success);
}
