// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./SecurityCouncilMemberElectionGovernor.sol";

import "./modules/SecurityCouncilNomineeElectionGovernorCountingUpgradeable.sol";
import "./modules/ArbitrumGovernorVotesQuorumFractionUpgradeable.sol";
import "./modules/SecurityCouncilNomineeElectionGovernorTiming.sol";

import "../SecurityCouncilMgmtUtils.sol";

// note: this contract assumes that there can only be one proposalId with state Active or Succeeded at a time
// (easy to override state() to return `Expired` if a proposal succeeded but hasn't executed after some time)

/// @title SecurityCouncilNomineeElectionGovernor
/// @notice Governor contract for selecting Security Council Nominees (phase 1 of the Security Council election process).
contract SecurityCouncilNomineeElectionGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorVotesUpgradeable,
    SecurityCouncilNomineeElectionGovernorCountingUpgradeable,
    ArbitrumGovernorVotesQuorumFractionUpgradeable,
    GovernorSettingsUpgradeable,
    OwnableUpgradeable,
    SecurityCouncilNomineeElectionGovernorTiming
{
    // todo: these parameters could be reordered to make more sense
    /// @notice parameters for `initialize`
    /// @param targetNomineeCount The target number of nominees to elect (6)
    /// @param firstNominationStartDate First election start date
    /// @param nomineeVettingDuration Duration of the nominee vetting period (expressed in blocks)
    /// @param nomineeVetter Address of the nominee vetter
    /// @param securityCouncilManager Security council manager contract
    /// @param token Token used for voting
    /// @param owner Owner of the governor (the Arbitrum DAO)
    /// @param quorumNumeratorValue Numerator of the quorum fraction (0.2% = 20)
    /// @param votingPeriod Duration of the voting period (expressed in blocks)
    struct InitParams {
        uint256 targetNomineeCount;
        Date firstNominationStartDate;
        uint256 nomineeVettingDuration;
        address nomineeVetter;
        ISecurityCouncilManager securityCouncilManager;
        SecurityCouncilMemberElectionGovernor securityCouncilMemberElectionGovernor;
        IVotesUpgradeable token;
        address owner;
        uint256 quorumNumeratorValue;
        uint256 votingPeriod;
    }

    /// @notice Information about a nominee election
    /// @param isContender Whether the account is a contender
    /// @param isExcluded Whether the account has been excluded by the nomineeVetter
    /// @param excludedNomineeCount The number of nominees that have been excluded by the nomineeVetter
    struct ElectionInfo {
        mapping(address => bool) isContender;
        mapping(address => bool) isExcluded;
        uint256 excludedNomineeCount;
    }

    /// @notice The target number of nominees to elect (6)
    uint256 public targetNomineeCount;

    /// @notice Address responsible for blocking non compliant nominees
    address public nomineeVetter;

    /// @notice Security council manager contract
    /// @dev    Used to execute the election result immediately if <= 6 compliant nominees are chosen
    ISecurityCouncilManager public securityCouncilManager;

    /// @notice Security council member election governor contract
    SecurityCouncilMemberElectionGovernor public securityCouncilMemberElectionGovernor;

    /// @notice Number of elections created
    uint256 public electionCount;

    /// @notice Maps proposalId to ElectionInfo
    mapping(uint256 => ElectionInfo) internal _elections;

    event NomineeVetterChanged(address indexed oldNomineeVetter, address indexed newNomineeVetter);
    event ContenderAdded(uint256 indexed proposalId, address indexed contender);
    event NomineeExcluded(uint256 indexed proposalId, address indexed nominee);

    error OnlyNomineeVetter();
    error CreateTooEarly(uint256 startTime);
    error AlreadyContender();
    error ProposalNotActive();
    error AccountInOtherCohort(Cohort cohort, address account);
    error ProposalNotSuccessful();
    error ProposalNotInVettingPeriod();
    error NomineeAlreadyExcluded();
    error CompliantNomineeTargetHit();
    error ProposalInVettingPeriod();
    error InsufficientCompliantNomineeCount();
    error ProposeDisabled();

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the governor
    function initialize(InitParams memory params) public initializer {
        __Governor_init("Security Council Nominee Election Governor");
        __GovernorVotes_init(params.token);
        __SecurityCouncilNomineeElectionGovernorCounting_init();
        __ArbitrumGovernorVotesQuorumFraction_init(params.quorumNumeratorValue);
        __GovernorSettings_init(0, params.votingPeriod, 0); // votingDelay and proposalThreshold are set to 0
        __SecurityCouncilNomineeElectionGovernorIndexingTiming_init(
            params.firstNominationStartDate, params.nomineeVettingDuration
        );
        _transferOwnership(params.owner);

        targetNomineeCount = params.targetNomineeCount;
        nomineeVetter = params.nomineeVetter;
        securityCouncilManager = params.securityCouncilManager;
        securityCouncilMemberElectionGovernor = params.securityCouncilMemberElectionGovernor;
    }

    /// @notice Allows the nominee vetter to call certain functions
    modifier onlyNomineeVetter() {
        if (msg.sender != nomineeVetter) {
            revert OnlyNomineeVetter();
        }
        _;
    }

    /**
     * permissionless state mutating functions *************
     */

    /// @notice Creates a new nominee election proposal.
    ///         Can be called by anyone every 6 months.
    /// @return proposalId The id of the proposal
    function createElection() external returns (uint256 proposalId) {
        // CHRIS: TODO: we need to check elections cannot have a time less than all the stages put together when initialising
        uint256 thisElectionStartTs = electionToTimestamp(electionCount);

        if (block.timestamp < thisElectionStartTs) {
            revert CreateTooEarly(thisElectionStartTs);
        }

        proposalId = GovernorUpgradeable.propose(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            electionIndexToDescription(electionCount)
        );

        electionCount++;
    }

    /// @notice Put `msg.sender` up for nomination. Must be called before a contender can receive votes.
    /// @dev    Can be called only while a proposal is active (in voting phase)
    ///         A contender cannot be a member of the opposite cohort.
    function addContender(uint256 proposalId) external {
        ElectionInfo storage election = _elections[proposalId];

        if (election.isContender[msg.sender]) {
            revert AlreadyContender();
        }

        ProposalState state = state(proposalId);

        if (state != ProposalState.Active) {
            revert ProposalNotActive();
        }

        // check to make sure the contender is not part of the other cohort (the cohort not currently up for election)
        if (securityCouncilManager.cohortIncludes(otherCohort(), msg.sender)) {
            revert AccountInOtherCohort(otherCohort(), msg.sender);
        }

        election.isContender[msg.sender] = true;

        emit ContenderAdded(proposalId, msg.sender);
    }

    /// @notice Allows the owner to change the nomineeVetter
    function setNomineeVetter(address _nomineeVetter) external onlyOwner {
        address oldNomineeVetter = nomineeVetter;
        nomineeVetter = _nomineeVetter;
        emit NomineeVetterChanged(oldNomineeVetter, _nomineeVetter);
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

    /// @notice Allows the nomineeVetter to exclude a noncompliant nominee.
    /// @dev    Can be called only after a nomninee election proposal has "succeeded" (voting has ended) and before the nominee vetting period has ended.
    ///         Will revert if the provided account is not a nominee (had less than the required votes).
    function excludeNominee(uint256 proposalId, address account) external onlyNomineeVetter {
        if (state(proposalId) != ProposalState.Succeeded) {
            revert ProposalNotSuccessful();
        }
        if (block.number > proposalVettingDeadline(proposalId)) {
            revert ProposalNotInVettingPeriod();
        }

        ElectionInfo storage election = _elections[proposalId];
        if (election.isExcluded[account]) {
            revert NomineeAlreadyExcluded();
        }

        election.isExcluded[account] = true;
        election.excludedNomineeCount++;

        emit NomineeExcluded(proposalId, account);
    }

    /// @notice Allows the nomineeVetter to explicitly include a nominee if there are fewer nominees than the target.
    /// @dev    Can be called only after a proposal has succeeded (voting has ended) and before the nominee vetting period has ended.
    ///         Will revert if the provided account is already a nominee
    function includeNominee(uint256 proposalId, address account) external onlyNomineeVetter {
        if (state(proposalId) != ProposalState.Succeeded) {
            revert ProposalNotSuccessful();
        }
        if (block.number > proposalVettingDeadline(proposalId)) {
            revert ProposalNotInVettingPeriod();
        }
        if (isNominee(proposalId, account)) {
            revert NomineeAlreadyAdded();
        }

        uint256 compliantNomineeCount =
            nomineeCount(proposalId) - _elections[proposalId].excludedNomineeCount;

        if (compliantNomineeCount >= targetNomineeCount) {
            revert CompliantNomineeTargetHit();
        }

        // can't include nominees from the other cohort
        if (securityCouncilManager.cohortIncludes(otherCohort(), account)) {
            revert AccountInOtherCohort(otherCohort(), account);
        }

        _addNominee(proposalId, account);
    }

    /**
     * internal/private state mutating functions
     */

    /// @dev    `GovernorUpgradeable` function to execute a proposal overridden to handle nominee elections.
    ///         Can be called by anyone via `execute` after voting and nominee vetting periods have ended.
    ///         If the number of compliant nominees is > the target number of nominees,
    ///         we move on to the next phase by calling the SecurityCouncilMemberElectionGovernor.
    /// @param  proposalId The id of the proposal
    function _execute(
        uint256 proposalId,
        address[] memory, /* targets */
        uint256[] memory, /* values */
        bytes[] memory, /* calldatas */
        bytes32 /*descriptionHash*/
    ) internal virtual override {
        if (block.number <= proposalVettingDeadline(proposalId)) {
            revert ProposalInVettingPeriod();
        }

        ElectionInfo storage election = _elections[proposalId];

        uint256 compliantNomineeCount = nomineeCount(proposalId) - election.excludedNomineeCount;

        if (compliantNomineeCount < targetNomineeCount) {
            revert InsufficientCompliantNomineeCount();
        }

        securityCouncilMemberElectionGovernor.proposeFromNomineeElectionGovernor();
    }

    /**
     * view/pure functions *************
     */

    /// @notice Normally "the number of votes required in order for a voter to become a proposer." But in our case it is 0.
    /// @dev    Since we only want proposals to be created via `createElection`, we set the proposal threshold to 0.
    ///         `createElection` determines the rules for creating a proposal.
    function proposalThreshold()
        public
        view
        virtual
        override(GovernorSettingsUpgradeable, GovernorUpgradeable)
        returns (uint256)
    {
        return 0;
    }

    /// @notice returns true if the account is a nominee for the given proposal and has not been excluded
    /// @param  proposalId The id of the proposal
    /// @param  account The account to check
    function isCompliantNominee(uint256 proposalId, address account) public view returns (bool) {
        return isNominee(proposalId, account) && !_elections[proposalId].isExcluded[account];
    }

    function compliantNominees(uint256 proposalId) public view returns (address[] memory) {
        ElectionInfo storage election = _elections[proposalId];
        address[] memory maybeCompliantNominees =
            SecurityCouncilNomineeElectionGovernorCountingUpgradeable.nominees(proposalId);
        return SecurityCouncilMgmtUtils.filterAddressesWithExcludeList(
            maybeCompliantNominees, election.isExcluded
        );
    }

    /// @notice returns cohort currently up for election
    function currentCohort() public view returns (Cohort) {
        return electionIndexToCohort(electionCount - 1);
    }

    /// @notice returns cohort not currently up for election
    function otherCohort() public view returns (Cohort) {
        return electionIndexToCohort(electionCount);
    }

    /// @notice Returns the cohort for a given `electionIndex`
    function electionIndexToCohort(uint256 electionIndex) public pure returns (Cohort) {
        return Cohort(electionIndex % 2);
    }

    // CHRIS: TODO: put these in both governors? or in a lib?
    /// @notice Returns the description for a given `electionIndex`
    function electionIndexToDescription(uint256 electionIndex)
        public
        pure
        returns (string memory)
    {
        return
            string.concat("Security Council Election #", StringsUpgradeable.toString(electionIndex));
    }

    /// @notice Returns the proposalId for a given `electionIndex`
    function electionIndexToProposalId(uint256 electionIndex) public pure returns (uint256) {
        return hashProposal(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            keccak256(bytes(electionIndexToDescription(electionIndex)))
        );
    }

    /// @notice returns true if the nominee has been excluded by the nomineeVetter for the given proposal
    function isExcluded(uint256 proposalId, address possibleExcluded) public view returns (bool) {
        return _elections[proposalId].isExcluded[possibleExcluded];
    }

    /// @notice returns the number of excluded nominees for the given proposal
    function excludedNomineeCount(uint256 proposalId) public view returns (uint256) {
        return _elections[proposalId].excludedNomineeCount;
    }

    /// @inheritdoc SecurityCouncilNomineeElectionGovernorCountingUpgradeable
    function isContender(uint256 proposalId, address possibleContender)
        public
        view
        virtual
        override
        returns (bool)
    {
        return _elections[proposalId].isContender[possibleContender];
    }

    /**
     * disabled functions *************
     */

    /// @notice Always reverts.
    /// @dev    `GovernorUpgradeable` function to create a proposal overridden to just revert.
    ///         We only want proposals to be created via `createElection`.
    function propose(address[] memory, uint256[] memory, bytes[] memory, string memory)
        public
        virtual
        override
        returns (uint256)
    {
        // revert(
        //     "SecurityCouncilNomineeElectionGovernor: Proposing is not allowed, call createElection instead"
        // );
        revert ProposeDisabled();
    }
}
