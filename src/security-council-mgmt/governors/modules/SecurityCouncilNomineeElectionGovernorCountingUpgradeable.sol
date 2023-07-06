// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";

/// @title  SecurityCouncilNomineeElectionGovernorCountingUpgradeable
/// @notice Counting module for the SecurityCouncilNomineeElectionGovernor
///         Keeps track of all contenders that receive enough votes to be a nominee
///         Voters can spread votes across multiple contenders
abstract contract SecurityCouncilNomineeElectionGovernorCountingUpgradeable is
    Initializable,
    GovernorUpgradeable
{
    // todo: better name
    struct NomineeElectionState {
        mapping(address => uint256) votesUsed;
        mapping(address => uint256) votesReceived;
        address[] nominees;
    }

    // proposalId => NomineeElectionState
    mapping(uint256 => NomineeElectionState) private _elections;

    // would this be more useful if reason was included?
    /// @notice Emitted when a vote is cast for a contender
    /// @param proposalId The id of the proposal
    /// @param voter The account that is casting the vote
    /// @param contender The contender that is receiving the vote
    /// @param votes The amount of votes that were just cast for the contender
    /// @param totalUsedVotes The total amount of votes the voter has used for this proposal
    /// @param totalUsableVotes The total amount of votes the voter has available for this proposal
    event VoteCastForContender(
        uint256 indexed proposalId,
        address indexed voter,
        address indexed contender,
        uint256 votes,
        uint256 totalUsedVotes,
        uint256 totalUsableVotes
    );

    event NewNominee(uint256 indexed proposalId, address indexed nominee);

    function __SecurityCouncilNomineeElectionGovernorCounting_init() internal onlyInitializing {}

    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "TODO: ???";
    }

    /// @notice returns true if the account has voted any amount for any contender in the proposal
    function hasVoted(uint256 proposalId, address account) public view override returns (bool) {
        return _elections[proposalId].votesUsed[account] > 0;
    }

    /// @dev there is no minimum quorum for nominations, so we just return true
    function _quorumReached(uint256) internal pure override returns (bool) {
        return true;
    }

    /// @dev the vote always succeeds, so we just return true
    function _voteSucceeded(uint256) internal pure override returns (bool) {
        return true;
    }

    /// @dev This function is responsible for counting votes when they are cast.
    ///      If this vote pushes the contender over the line, then the contender is added to the nominees
    ///      and only the necessary amount of votes will be deducted from the voter.
    /// @param proposalId the id of the proposal
    /// @param account the account that is casting the vote
    /// @param weight the amount of vote that account held at time of snapshot
    /// @param params abi encoded (contender, votes) where votes is the amount of votes the account is using for this contender
    function _countVote(
        uint256 proposalId,
        address account,
        uint8,
        uint256 weight,
        bytes memory params
    ) internal virtual override {
        require(params.length == 64, "SecurityCouncilNomineeElectionGovernorCountingUpgradeable: Must cast vote with abi encoded (contender, votes)");

        // params is encoded as (address contender, uint256 votes)
        (address contender, uint256 votes) = abi.decode(params, (address, uint256));

        require(
            _isContender(proposalId, contender),
            "SecurityCouncilNomineeElectionGovernorCountingUpgradeable: Contender is not eligible"
        );

        require(
            !isNominee(proposalId, contender),
            "SecurityCouncilNomineeElectionGovernorCountingUpgradeable: Contender already has enough votes"
        );

        NomineeElectionState storage election = _elections[proposalId];
        uint256 prevVotesUsed = election.votesUsed[account];

        require(
            votes + prevVotesUsed <= weight,
            "SecurityCouncilNomineeElectionGovernorCountingUpgradeable: Not enough tokens to cast this vote"
        );

        uint256 prevVotesReceived = election.votesReceived[contender];
        uint256 votesThreshold = quorum(proposalSnapshot(proposalId));

        uint256 actualVotes = votes;

        if (prevVotesReceived + votes >= votesThreshold) {
            // we pushed the contender over the line
            // we should only give the contender enough votes to get to the line so that we don't waste votes
            actualVotes = votesThreshold - prevVotesReceived;

            // push the contender to the nominees
            election.nominees.push(contender);

            emit NewNominee(proposalId, contender);
        }

        election.votesUsed[account] = prevVotesUsed + actualVotes;
        election.votesReceived[contender] = prevVotesReceived + actualVotes;

        emit VoteCastForContender({
            proposalId: proposalId,
            voter: account,
            contender: contender,
            votes: actualVotes,
            totalUsedVotes: prevVotesUsed + actualVotes,
            totalUsableVotes: weight
        });
    }

    /// @notice Returns true if the contender has enough votes to be a nominee
    function isNominee(uint256 proposalId, address contender) public view returns (bool) {
        return
            _elections[proposalId].votesReceived[contender] >= quorum(proposalSnapshot(proposalId));
    }

    /// @notice Returns the number of nominees for a given proposal
    function nomineeCount(uint256 proposalId) public view returns (uint256) {
        return _elections[proposalId].nominees.length;
    }

    /// @notice Returns the list of nominees for a given proposal
    function nominees(uint256 proposalId) public view returns (address[] memory) {
        return _elections[proposalId].nominees;
    }

    /// @notice Returns the amount of votes an account has used for a given proposal
    function votesUsed(uint256 proposalId, address account) public view returns (uint256) {
        return _elections[proposalId].votesUsed[account];
    }

    /// @notice Returns the amount of votes a contender has received for a given proposal
    function votesReceived(uint256 proposalId, address contender) public view returns (uint256) {
        return _elections[proposalId].votesReceived[contender];
    }

    /// @dev Returns true if the account is a contender for the proposal
    function _isContender(uint256 proposalId, address possibleContender)
        internal
        view
        virtual
        returns (bool);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
