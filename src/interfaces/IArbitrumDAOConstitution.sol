// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IArbitrumDAOConstitution {
    function constitutionHash() external view returns (bytes32);
    function setConstitutionHash(bytes32 _constitutionHash) external;
    function owner() external view returns (address);
}
