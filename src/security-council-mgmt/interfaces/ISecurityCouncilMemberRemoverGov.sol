// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ISecurityCouncilManager.sol";
import "../../L2ArbitrumGovernor.sol";

interface ISecurityCouncilMemberRemoverGov {
    function initialize(
        address _proposer,
        ISecurityCouncilManager _securityCouncilManager,
        IVotesUpgradeable _token,
        TimelockControllerUpgradeable _timelock,
        address _owner,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumNumerator,
        uint256 _proposalThreshold,
        uint64 _minPeriodAfterQuorum
    ) external;
    function proposeRemoveMember(address memberToRemove, string memory description)
        external
        returns (uint256);
}
