// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

struct L2ChainToUpdate {
    address inbox;
    address securityCouncilUpgradeExecutor;
    uint256 chainID;
}

interface IL1SecurityCouncilUpdateRouter {
    function handleUpdateMembers(
        address[] calldata _membersToAdd,
        address[] calldata _membersToRemove
    ) external payable;
    function removeL2Chain(uint256 chainID) external returns (bool);
    function registerL2Chain(L2ChainToUpdate memory l2ChainToUpdate) external;
}
