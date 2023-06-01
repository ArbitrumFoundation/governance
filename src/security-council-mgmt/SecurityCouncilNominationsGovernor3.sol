// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorPreventLateQuorumUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

import "../L2ArbitrumGovernor.sol";
import "./SecurityCouncilNominationsManager.sol";
import "./interfaces/ISecurityCouncilManager.sol";
import "./ArbitrumGovernorVotesQuorumFractionUpgradeable.sol";

abstract contract SecurityCouncilNomineeElectionGovernorCounting is Initializable, GovernorUpgradeable {
    // todo: better name
    struct NomineeElectionState {
        mapping(address => uint256) tokensUsed;
        mapping(address => uint256) votes;
        address[] nominees;
    }

    // proposalId => NomineeElectionState
    mapping(uint256 => NomineeElectionState) private _elections;

    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "TODO: ???";
    }

    function hasVoted(
        uint256 proposalId, 
        address account
    ) 
        public 
        view 
        override
        returns (bool) 
    {
        // should this return true if they've cast any amount of votes? or if they've cast all of their votes?
        revert("TODO");
    }

    // there is no minimum quorum for nominations, so we just return true
    function _quorumReached(uint256) internal pure override returns (bool) {
        return true;
    }

    // the vote always succeeds, so we just return true
    function _voteSucceeded(uint256) internal pure override returns (bool) {
        return true;
    }

    function _countVote(
        uint256 proposalId,
        address account,
        uint8,
        uint256 weight,
        bytes memory params
    ) internal virtual override {
        // let's say params is (address candidate, uint256 tokens)
        (address candidate, uint256 tokens) = abi.decode(params, (address, uint256));

        require(_isContender(proposalId, candidate), "Candidate is not eligible");

        NomineeElectionState storage election = _elections[proposalId];

        // weight is the number of tokens that account has at the time of the vote
        // make sure tokens + previously used tokens is less than or equal to weight
        uint256 previouslyUsedTokens = election.tokensUsed[account];
        require(tokens + previouslyUsedTokens <= weight, "Not enough tokens to cast this vote");

        // add to tokensUsed
        election.tokensUsed[account] = previouslyUsedTokens + tokens;

        // add tokens to the candidate
        uint256 oldVotesForCandidate = election.votes[candidate];
        election.votes[candidate] = oldVotesForCandidate + tokens;

        // if this vote put the candidate over the line, push to nominees
        uint256 votesNeeded = quorum(proposalSnapshot(proposalId));
        if (oldVotesForCandidate < votesNeeded && oldVotesForCandidate + tokens >= votesNeeded) {
            election.nominees.push(candidate);
            // emit some event like CandidateSuccessfullyNominated(proposalId, candidate);
        }
    }

    function nomineeCount(uint256 proposalId) public view returns (uint256) {
        return _elections[proposalId].nominees.length;
    }

    function nominees(uint256 proposalId) public view returns (address[] memory) {
        return _elections[proposalId].nominees;
    }

    function _isContender(uint256 proposalId, address candidate) internal view virtual returns (bool);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}


contract ArbitrumNomineeElectionGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorVotesUpgradeable,
    SecurityCouncilNomineeElectionGovernorCounting,
    ArbitrumGovernorVotesQuorumFractionUpgradeable,
    GovernorSettingsUpgradeable,
    OwnableUpgradeable
{
    // todo: set these in the constructor / initializer
    uint256 public targetNomineeCount;
    Cohort public firstCohort;
    uint256 public firstNominationStartTime;
    uint256 public nominationFrequency;
    SecurityCouncilManager public securityCouncilManager;

    // number of nominee selection proposals that have been created
    uint256 public proposalCount;

    // maps proposalId to map of address to bool indicating whether the candidate is a contender for nomination
    mapping(uint256 => mapping(address => bool)) public contenders;

    // override propose to revert
    function propose(
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        string memory
    ) public virtual override returns (uint256) {
        revert("Proposing is not allowed, call createElection instead");
    }

    // proposal threshold is 0 because we call propose via createElection
    function proposalThreshold() public view virtual override(GovernorSettingsUpgradeable, GovernorUpgradeable) returns (uint256) {
        return 0;
    }

    function createElection() external returns (uint256 proposalIndex, uint256 proposalId) {
        require(block.timestamp >= firstNominationStartTime + nominationFrequency * proposalCount, "Not enough time has passed since the last election");

        // create a proposal with dummy address and value
        // make the calldata abi encoded (proposalIndex)
        // this is necessary because we need to know the proposalIndex in order to know which cohort a proposal is for when we execute

        proposalIndex = proposalCount;
        proposalCount++;

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encode(proposalIndex);

        proposalId = GovernorUpgradeable.propose(targets, values, calldatas, proposalIndexToDescription(proposalIndex));
    }

    function _execute(
        uint256 /* proposalId */,
        address[] memory /* targets */,
        uint256[] memory /* values */,
        bytes[] memory calldatas,
        bytes32 /*descriptionHash*/
    ) internal virtual override {
        uint256 proposalIndex = abi.decode(calldatas[0], (uint256));
        uint256 proposalId = proposalIndexToProposalId(proposalIndex);

        uint256 numNominated = nomineeCount(proposalId);

        if (numNominated > targetNomineeCount) {
            // todo:
            // call the SecurityCouncilMemberElectionGovernor to execute the election
            // the SecurityCouncilMemberElectionGovernor will call back into this contract to look up nominees
            return;
        }

        address[] memory nominees;
        if (numNominated < targetNomineeCount) {
            // todo: randomly select some number of candidates from current cohort to add to the nominees
            // nominees = ...
        }
        else {
            nominees = SecurityCouncilNomineeElectionGovernorCounting.nominees(proposalId);
        }
        
        // call the SecurityCouncilManager to switch out the security council members
        securityCouncilManager.executeElectionResult(nominees, proposalIndexToCohort(proposalIndex));
    }

    function addContender(uint256 proposalId, address account) external {
        ProposalState state = state(proposalId);
        require(state == ProposalState.Active, "Proposal is not active");

        // todo: check to make sure the candidate is eligible (not part of the other cohort, etc.)

        contenders[proposalId][account] = true;
    }

    function _isContender(uint256 proposalId, address candidate) internal view virtual override returns (bool) {
        return contenders[proposalId][candidate];
    }

    function proposalIndexToCohort(uint256 proposalIndex) public view returns (Cohort) {
        return Cohort((uint256(firstCohort) + proposalIndex) % 2);
    }

    function proposalIndexToDescription(uint256 proposalIndex) public pure returns (string memory) {
        return string.concat("Nominee Selection #", StringsUpgradeable.toString(proposalIndex));
    }

    function proposalIndexToProposalId(uint256 proposalIndex) public pure returns (uint256) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encode(proposalIndex);

        return hashProposal(targets, values, calldatas, keccak256(bytes(proposalIndexToDescription(proposalIndex))));
    }
}
