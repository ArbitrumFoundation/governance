// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorPreventLateQuorumUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../../L2ArbitrumGovernor.sol";
import "./SecurityCouncilNominationsManager.sol";
import "../interfaces/ISecurityCouncilManager.sol";

abstract contract ArbitrumGovernorVotesQuorumFractionUpgradeable is Initializable, GovernorVotesQuorumFractionUpgradeable {
    /// @notice address for which votes will not be counted toward quorum
    /// @dev    A portion of the Arbitrum tokens will be held by entities (eg the treasury) that
    ///         are not eligible to vote. However, even if their voting/delegation is restricted their
    ///         tokens will still count towards the total supply, and will therefore affect the quorom.
    ///         Restricted addresses should be forced to delegate their votes to this special exclude
    ///         addresses which is not counted when calculating quorum
    ///         Example address that should be excluded: DAO treasury, foundation, unclaimed tokens,
    ///         burned tokens and swept (see TokenDistributor) tokens.
    ///         Note that Excluded Address is a readable name with no code of PK associated with it, and thus can't vote.
    address public constant EXCLUDE_ADDRESS = address(0xA4b86);

    function __ArbitrumGovernorVotesQuorumFraction_init(uint256 quorumNumeratorValue) internal onlyInitializing {
        __GovernorVotesQuorumFraction_init(quorumNumeratorValue);
    }

    /// @notice Get "circulating" votes supply; i.e., total minus excluded vote exclude address.
    function getPastCirculatingSupply(uint256 blockNumber) public view virtual returns (uint256) {
        return
            token.getPastTotalSupply(blockNumber) - token.getPastVotes(EXCLUDE_ADDRESS, blockNumber);
    }

    /// @notice Calculates the quorum size, excludes token delegated to the exclude address
    function quorum(uint256 blockNumber)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return (getPastCirculatingSupply(blockNumber) * quorumNumerator(blockNumber))
            / quorumDenominator();
    }

    /// @inheritdoc GovernorVotesQuorumFractionUpgradeable
    function quorumDenominator()
        public
        pure
        virtual
        override
        returns (uint256)
    {
        // update to 10k to allow for higher precision
        return 10_000;
    }
    
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

// this contract is the same as SecurityCouncilNominationsGovernor, 
// but instead of using L2ArbitrumGovernor as a parent and overriding some of its modules like counting/timelock, 
// it uses OZ governor contracts as parents and just inherits what it needs
abstract contract SecurityCouncilNominationsGovernor2 is
    Initializable,
    GovernorUpgradeable,
    GovernorVotesUpgradeable,
    ArbitrumGovernorVotesQuorumFractionUpgradeable,
    GovernorSettingsUpgradeable,
    OwnableUpgradeable
{
    struct NominationElection {
        uint256 electionId; // NominationsManager's electionId
        mapping(address => uint256) nominationsTokensUsed;
        mapping(address => uint256) nominationsVotes;
        address[] successfullyNominatedCandidates;
    }

    SecurityCouncilNominationsManager public nominationsManager;

    // proposalId => GovernorNominationElection
    mapping(uint256 => NominationElection) nominationElections;

    /// @param _token The token to read vote delegation from
    /// @param _owner The executor through which all upgrades should be finalised
    /// @param _votingDelay The delay between a proposal submission and voting starts
    /// @param _votingPeriod The period for which the vote lasts
    /// @param _quorumNumerator The proportion of the circulating supply required to reach a quorum
    function initialize(
        IVotesUpgradeable _token,
        address _owner,
        SecurityCouncilNominationsManager _nominationsManager,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumNumerator // 0.2%, required for any candidate to become a nominee for next phases
    ) external initializer {
        __Governor_init("TODO: some name here like NominationsGovernor or something");
        __GovernorVotes_init(_token);
        __ArbitrumGovernorVotesQuorumFraction_init(_quorumNumerator);
        __GovernorSettings_init(_votingDelay, _votingPeriod, 0);
        _transferOwnership(_owner);

        nominationsManager = _nominationsManager;
    }

    modifier onlyManager {
        require(msg.sender == address(nominationsManager), "Only the manager can call this");
        _;
    }

    ////////////// Counting //////////////

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

        require(_isCandidateEligible(proposalId, candidate), "Candidate is not eligible");

        NominationElection storage election = nominationElections[proposalId];

        // weight is the number of tokens that account has at the time of the vote
        // make sure tokens + previously used tokens is less than or equal to weight
        uint256 previouslyUsedTokens = election.nominationsTokensUsed[account];
        require(tokens + previouslyUsedTokens <= weight, "Not enough tokens to cast this vote");

        // add to nominationsTokensUsed
        election.nominationsTokensUsed[account] = previouslyUsedTokens + tokens;

        // add tokens to the candidate
        uint256 oldVotesForCandidate = election.nominationsVotes[candidate];
        election.nominationsVotes[candidate] = oldVotesForCandidate + tokens;

        // if this vote put the candidate over the line, push to successfullyNominatedCandidates
        uint256 votesNeeded = quorum(proposalSnapshot(proposalId));
        if (oldVotesForCandidate < votesNeeded && oldVotesForCandidate + tokens >= votesNeeded) {
            election.successfullyNominatedCandidates.push(candidate);
            // emit some event like CandidateSuccessfullyNominated(proposalId, candidate);
        }
    }

    ////////////// End Counting //////////////

    ////////////// Other Overrides //////////////

    // override propose such that only the manager contract can call it
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override onlyManager returns (uint256) {
        uint256 proposalId = super.propose(targets, values, calldatas, description);

        // set the electionId for this proposal
        // alternatively, we can decode the calldata and get the electionId from there
        uint256 electionId = nominationsManager.nominationsCount();
        nominationElections[proposalId].electionId = electionId;

        return proposalId;
    }

    function proposalThreshold() public view virtual override(GovernorSettingsUpgradeable, GovernorUpgradeable) returns (uint256) {
        return 0;
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

    ////////////// End Other Overrides //////////////

    // returns true if the candidate has enough votes to be nominated
    function isCandidateSuccessfullyNominated(uint256 proposalId, address candidate) public view returns (bool) {
        return nominationElections[proposalId].nominationsVotes[candidate] >= quorum(proposalSnapshot(proposalId));
    }

    function successfullyNominatedCandidatesCount(uint256 proposalId) public view returns (uint256) {
        return nominationElections[proposalId].successfullyNominatedCandidates.length;
    }

    function successfullyNominatedCandidates(uint256 proposalId) public view returns (address[] memory) {
        return nominationElections[proposalId].successfullyNominatedCandidates;
    }

    // check the manager contract to see if the candidate is eligible
    function _isCandidateEligible(uint256 proposalId, address candidate) internal view returns (bool) {
        uint256 electionId = nominationElections[proposalId].electionId;
        return nominationsManager.isCandidateUpForNomination(electionId, candidate);
    }
}