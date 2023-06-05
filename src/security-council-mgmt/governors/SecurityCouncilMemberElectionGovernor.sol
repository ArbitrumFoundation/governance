// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

import "./modules/ArbitrumGovernorVotesQuorumFractionUpgradeable.sol";
import "./modules/SecurityCouncilMemberElectionGovernorCounting.sol";
import "./SecurityCouncilNomineeElectionGovernor.sol";

import "../SecurityCouncilManager.sol";


// narrows a set of nominees to a set of 6 members
// proposals are created by the NomineeElectionGovernor
contract SecurityCouncilMemberElectionGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorVotesUpgradeable,
    SecurityCouncilMemberElectionGovernorCounting,
    ArbitrumGovernorVotesQuorumFractionUpgradeable,
    GovernorSettingsUpgradeable,
    OwnableUpgradeable
{
    // todo:
    // - initializer

    SecurityCouncilNomineeElectionGovernor public nomineeElectionGovernor;
    SecurityCouncilManager public securityCouncilManager;

    // maps MemberElection proposalId to NomineeElection proposalIndex (todo: name this better)
    mapping(uint256 => uint256) public proposalIdToNomineeElectionProposalIndex;

    modifier onlyNomineeElectionGovernor {
        require(msg.sender == address(nomineeElectionGovernor), "Only the nominee election governor can call this function");
        _;
    }

    /// @notice Allows the owner to make calls from the governor
    /// @dev    See {L2ArbitrumGovernor-relay}
    function relay(address target, uint256 value, bytes calldata data)
        external
        virtual
        override
        onlyOwner
    {
        AddressUpgradeable.functionCallWithValue(target, data, value);
    }

    // override propose to revert
    function propose(
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        string memory
    ) public virtual override returns (uint256) {
        revert("Proposing is not allowed, call proposeFromNomineeElectionGovernor instead");
    }

    function proposalThreshold() public pure override(GovernorSettingsUpgradeable, GovernorUpgradeable) returns (uint256) {
        return 0;
    }

    function proposeFromNomineeElectionGovernor(uint256 nomineeElectionProposalIndex) external onlyNomineeElectionGovernor {
        uint256 proposalId = GovernorUpgradeable.propose(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            proposalIndexToDescription(nomineeElectionProposalIndex)
        );

        proposalIdToNomineeElectionProposalIndex[proposalId] = nomineeElectionProposalIndex;
    }

    function _execute(
        uint256 proposalId,
        address[] memory /* targets */,
        uint256[] memory /* values */,
        bytes[] memory /* calldatas */,
        bytes32 /* descriptionHash */
    ) internal override {
        uint256 nomineeElectionProposalIndex = proposalIdToNomineeElectionProposalIndex[proposalId];
        Cohort cohort = nomineeElectionGovernor.proposalIndexToCohort(nomineeElectionProposalIndex);

        // we know that the list is full because we checked it in _voteSucceeded
        address[] memory newMembers = _getTopCandidates(proposalId);

        securityCouncilManager.executeElectionResult(newMembers, cohort);
    }

    function proposalIndexToDescription(uint256 proposalIndex) public pure returns (string memory) {
        return string.concat("Member Election for Nominee Election #", StringsUpgradeable.toString(proposalIndex));
    }

    // proposalId is the id of the member election proposal (this contract)
    // we need to map the proposalId to the nominee election proposalId
    function _isCompliantNominee(uint256 proposalId, address nominee) internal view override returns (bool) {
        uint256 nomineeElectionProposalIndex = proposalIdToNomineeElectionProposalIndex[proposalId];
        uint256 nomineeElectionProposalId = nomineeElectionGovernor.proposalIndexToProposalId(nomineeElectionProposalIndex);
        return nomineeElectionGovernor.isCompliantNominee(nomineeElectionProposalId, nominee);
    }
}