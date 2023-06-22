// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

struct GovernedSecurityCouncil {
    address inbox;
    address securityCouncilUpgradeExecutor;
    uint256 chainID;
}

interface IL1SecurityCouncilUpdateRouter {
    function initialize(
        address _governanceChainInbox,
        address _l1SecurityCouncilUpgradeExecutor,
        address _l2SecurityCouncilManager,
        GovernedSecurityCouncil[] memory _initiall2ChainsToUpdateArr,
        address _owner,
        uint256 minDelay
    ) external;
    function scheduleUpdateMembers(bytes calldata _membersData) external;
    function removeSecurityCouncil(uint256 index) external returns (bool);
    function registerSecurityCouncil(GovernedSecurityCouncil memory securityCouncil) external;
}
