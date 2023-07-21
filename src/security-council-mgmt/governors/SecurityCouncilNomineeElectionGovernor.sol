// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/ISecurityCouncilMemberElectionGovernor.sol";
import "../interfaces/ISecurityCouncilNomineeElectionGovernor.sol";
import "./modules/SecurityCouncilNomineeElectionGovernorCountingUpgradeable.sol";
import "./modules/ArbitrumGovernorVotesQuorumFractionUpgradeable.sol";
import "./modules/SecurityCouncilNomineeElectionGovernorTiming.sol";
import "./modules/ElectionGovernor.sol";
import "../SecurityCouncilMgmtUtils.sol";

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
    SecurityCouncilNomineeElectionGovernorTiming,
    ElectionGovernor,
    ISecurityCouncilNomineeElectionGovernor
{
    /// @notice parameters for `initialize`
    /// @param firstNominationStartDate First election start date
    /// @param nomineeVettingDuration Duration of the nominee vetting period (expressed in blocks)
    /// @param nomineeVetter Address of the nominee vetter
    /// @param securityCouncilManager Security council manager contract
    /// @param token Token used for voting
    /// @param owner Owner of the governor (the Arbitrum DAO)
    /// @param quorumNumeratorValue Numerator of the quorum fraction (0.2% = 20)
    /// @param votingPeriod Duration of the voting period (expressed in blocks)
    ///                     Note that the voting period + nominee vetting duration must be << than 6 months to ensure elections dont overlap
    struct InitParams {
        Date firstNominationStartDate;
        uint256 nomineeVettingDuration;
        address nomineeVetter;
        ISecurityCouncilManager securityCouncilManager;
        ISecurityCouncilMemberElectionGovernor securityCouncilMemberElectionGovernor;
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

    /// @notice Address responsible for blocking non compliant nominees
    address public nomineeVetter;

    /// @notice Security council manager contract
    /// @dev    Used to execute the election result immediately if <= 6 compliant nominees are chosen
    ISecurityCouncilManager public securityCouncilManager;

    /// @notice Security council member election governor contract
    ISecurityCouncilMemberElectionGovernor public securityCouncilMemberElectionGovernor;

    /// @notice Number of elections created
    uint256 public electionCount;

    /// @notice Maps proposalId to ElectionInfo
    mapping(uint256 => ElectionInfo) internal _elections;

    event NomineeVetterChanged(address indexed oldNomineeVetter, address indexed newNomineeVetter);
    event ContenderAdded(uint256 indexed proposalId, address indexed contender);
    event NomineeExcluded(uint256 indexed proposalId, address indexed nominee);

    error OnlyNomineeVetter();
    error CreateTooEarly(uint256 blockTimestamp, uint256 startTime);
    error AlreadyContender(address contender);
    error ProposalNotActive(ProposalState state);
    error AccountInOtherCohort(Cohort cohort, address account);
    error ProposalNotSucceededState(ProposalState state);
    error ProposalNotInVettingPeriod(uint256 blockNumber, uint256 vettingDeadline);
    error NomineeAlreadyExcluded(address nominee);
    error CompliantNomineeTargetHit(uint256 nomineeCount, uint256 expectedCount);
    error ProposalInVettingPeriod(uint256 blockNumber, uint256 vettingDeadline);
    error InsufficientCompliantNomineeCount(uint256 compliantNomineeCount, uint256 expectedCount);
    error ProposeDisabled();
    error NotNominee(address nominee);
    error ProposalIdMismatch(uint256 nomineeProposalId, uint256 memberProposalId);
    error QuorumNumeratorTooLow(uint256 quorumNumeratorValue);
    error CastVoteDisabled();

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the governor
    function initialize(InitParams memory params) public initializer {
        __Governor_init("SecurityCouncilNomineeElectionGovernor");
        __GovernorVotes_init(params.token);
        __SecurityCouncilNomineeElectionGovernorCounting_init();
        __ArbitrumGovernorVotesQuorumFraction_init(params.quorumNumeratorValue);
        __GovernorSettings_init(0, params.votingPeriod, 0); // votingDelay and proposalThreshold are set to 0
        __SecurityCouncilNomineeElectionGovernorIndexingTiming_init(
            params.firstNominationStartDate, params.nomineeVettingDuration
        );
        _transferOwnership(params.owner);

        nomineeVetter = params.nomineeVetter;
        if (!Address.isContract(address(params.securityCouncilManager))) {
            revert NotAContract(address(params.securityCouncilManager));
        }
        securityCouncilManager = params.securityCouncilManager;
        if (!Address.isContract(address(params.securityCouncilMemberElectionGovernor))) {
            revert NotAContract(address(params.securityCouncilMemberElectionGovernor));
        }
        securityCouncilMemberElectionGovernor = params.securityCouncilMemberElectionGovernor;

        // elsewhere we make assumptions that the number of nominees
        // is not greater than 500
        // This value can still be updated via updateQuorumNumerator to a lower value
        // if it is deemed ok, however we put a quick check here as a reminder
        if ((quorumDenominator() / params.quorumNumeratorValue) > 500) {
            revert QuorumNumeratorTooLow(params.quorumNumeratorValue);
        }
    }

    /// @notice Allows the nominee vetter to call certain functions
    ///         Vetting takes places in a specific time period between voting and execution
    ///         Vetting cannot occur outside of this time slot
    modifier onlyNomineeVetterInVettingPeriod(uint256 proposalId) {
        if (msg.sender != nomineeVetter) {
            revert OnlyNomineeVetter();
        }

        // voting is over and the proposal must have succeeded, not active or executed
        ProposalState state = state(proposalId);
        if (state != ProposalState.Succeeded) {
            revert ProposalNotSucceededState(state);
        }

        // the proposal must not have passed the vetting deadline
        uint256 vettingDeadline = proposalVettingDeadline(proposalId);
        if (block.number > vettingDeadline) {
            revert ProposalNotInVettingPeriod(block.number, vettingDeadline);
        }

        _;
    }

    /// @notice Creates a new nominee election proposal.
    ///         Can be called by anyone every 6 months.
    /// @return proposalId The id of the proposal
    function createElection() external returns (uint256 proposalId) {
        // each election has a deterministic start time
        uint256 thisElectionStartTs = electionToTimestamp(electionCount);
        if (block.timestamp < thisElectionStartTs) {
            revert CreateTooEarly(block.timestamp, thisElectionStartTs);
        }

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory callDatas,
            string memory description
        ) = getProposeArgs(electionCount);

        proposalId = GovernorUpgradeable.propose(targets, values, callDatas, description);

        electionCount++;
    }

    /// @notice Put `msg.sender` up for nomination. Must be called before a contender can receive votes.
    ///         Contenders are expected to control an address than can create a signature that would be a
    ///         recognised by a Gnosis Safe. They need to be able to do this with this same address on each of the
    ///         chains where the Security Council is active. It is expected that the nominee vetter will check this
    ///         during the vetting phase and exclude any contenders which dont meet this criteria.
    /// @dev    Can be called only while a proposal is active (in voting phase)
    ///         A contender cannot be a member of the opposite cohort.
    function addContender(uint256 proposalId) external {
        ElectionInfo storage election = _elections[proposalId];

        if (election.isContender[msg.sender]) {
            revert AlreadyContender(msg.sender);
        }

        ProposalState state = state(proposalId);
        if (state != ProposalState.Active) {
            revert ProposalNotActive(state);
        }

        // check to make sure the contender is not part of the other cohort (the cohort not currently up for election)
        // this only checks against the current the current other cohort, and against the current cohort membership
        // in the security council, so changes to those will mean this check will be inconsistent.
        // this check then is only a relevant check when the elections are running as expected - one at a time,
        // every 6 months. Updates to the sec council manager using methods other than replaceCohort can effect this check
        // and it's expected that the entity making those updates understands this.
        if (securityCouncilManager.cohortIncludes(otherCohort(), msg.sender)) {
            revert AccountInOtherCohort(otherCohort(), msg.sender);
        }

        election.isContender[msg.sender] = true;

        emit ContenderAdded(proposalId, msg.sender);
    }

    /// @notice Allows the owner to change the nomineeVetter
    function setNomineeVetter(address _nomineeVetter) external onlyGovernance {
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
    function excludeNominee(uint256 proposalId, address nominee)
        external
        onlyNomineeVetterInVettingPeriod(proposalId)
    {
        ElectionInfo storage election = _elections[proposalId];
        if (election.isExcluded[nominee]) {
            revert NomineeAlreadyExcluded(nominee);
        }
        if (!isNominee(proposalId, nominee)) {
            revert NotNominee(nominee);
        }

        election.isExcluded[nominee] = true;
        election.excludedNomineeCount++;

        emit NomineeExcluded(proposalId, nominee);
    }

    /// @notice Allows the nomineeVetter to explicitly include a nominee if there are fewer nominees than the target.
    /// @dev    Can be called only after a proposal has succeeded (voting has ended) and before the nominee vetting period has ended.
    ///         Will revert if the provided account is already a nominee
    ///         The Constitution must be followed adding nominees. For example this method can be used by the Foundation to add a
    ///         random member of the outgoing security council, if less than 6 members meet the threshold to become a nominee
    function includeNominee(uint256 proposalId, address account)
        external
        onlyNomineeVetterInVettingPeriod(proposalId)
    {
        if (isNominee(proposalId, account)) {
            revert NomineeAlreadyAdded(account);
        }

        uint256 cnCount = compliantNomineeCount(proposalId);
        uint256 cohortSize = securityCouncilManager.cohortSize();
        if (cnCount >= cohortSize) {
            revert CompliantNomineeTargetHit(cnCount, cohortSize);
        }

        // can't include nominees from the other cohort (the cohort not currently up for election)
        // this only checks against the current the current other cohort, and against the current cohort membership
        // in the security council, so changes to those will mean this check will be inconsistent.
        // this check then is only a relevant check when the elections are running as expected - one at a time,
        // every 6 months. Updates to the sec council manager using methods other than replaceCohort can effect this check
        // and it's expected that the entity making those updates understands this.
        if (securityCouncilManager.cohortIncludes(otherCohort(), account)) {
            revert AccountInOtherCohort(otherCohort(), account);
        }

        _addNominee(proposalId, account);
    }

    /// @dev    `GovernorUpgradeable` function to execute a proposal overridden to handle nominee elections.
    ///         Can be called by anyone via `execute` after voting and nominee vetting periods have ended.
    ///         If the number of compliant nominees is > the target number of nominees,
    ///         we move on to the next phase by calling the SecurityCouncilMemberElectionGovernor.
    /// @param  proposalId The id of the proposal
    function _execute(
        uint256 proposalId,
        address[] memory, /* targets */
        uint256[] memory, /* values */
        bytes[] memory callDatas,
        bytes32 /*descriptionHash*/
    ) internal virtual override {
        // we can only execute when the vetting deadline has passed
        uint256 vettingDeadline = proposalVettingDeadline(proposalId);
        if (block.number <= vettingDeadline) {
            revert ProposalInVettingPeriod(block.number, vettingDeadline);
        }

        uint256 cnCount = compliantNomineeCount(proposalId);
        uint256 cohortSize = securityCouncilManager.cohortSize();
        if (cnCount < cohortSize) {
            revert InsufficientCompliantNomineeCount(cnCount, cohortSize);
        }

        uint256 electionIndex = extractElectionIndex(callDatas);
        uint256 memberElectionProposalId =
            securityCouncilMemberElectionGovernor.proposeFromNomineeElectionGovernor(electionIndex);

        // proposals in the member and nominee governors should have the same ids
        // so we do a safety check here to ensure this is the case
        if (memberElectionProposalId != proposalId) {
            revert ProposalIdMismatch(proposalId, memberElectionProposalId);
        }
    }

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

    /// @inheritdoc ISecurityCouncilNomineeElectionGovernor
    function isCompliantNominee(uint256 proposalId, address account) public view returns (bool) {
        return isNominee(proposalId, account) && !_elections[proposalId].isExcluded[account];
    }

    /// @inheritdoc ISecurityCouncilNomineeElectionGovernor
    function compliantNominees(uint256 proposalId) public view returns (address[] memory) {
        ElectionInfo storage election = _elections[proposalId];
        address[] memory maybeCompliantNominees =
            SecurityCouncilNomineeElectionGovernorCountingUpgradeable.nominees(proposalId);
        return SecurityCouncilMgmtUtils.filterAddressesWithExcludeList(
            maybeCompliantNominees, election.isExcluded
        );
    }

    /// @notice Current number of compliant nominees for the proposal
    function compliantNomineeCount(uint256 proposalId) public view returns (uint256) {
        return nomineeCount(proposalId) - _elections[proposalId].excludedNomineeCount;
    }

    /// @notice Returns cohort currently up for election
    function currentCohort() public view returns (Cohort) {
        // current cohort is at electionCount - 1
        return electionCount == 0 ? Cohort.FIRST : electionIndexToCohort(electionCount - 1);
    }

    /// @notice Returns cohort not currently up for election
    function otherCohort() public view returns (Cohort) {
        // previous cohort is at electionCount - 2
        return (electionCount < 2) ? Cohort.SECOND : electionIndexToCohort(electionCount - 2);
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

    /// @notice Always reverts.
    /// @dev    `GovernorUpgradeable` function to create a proposal overridden to just revert.
    ///         We only want proposals to be created via `createElection`.
    function propose(address[] memory, uint256[] memory, bytes[] memory, string memory)
        public
        virtual
        override
        returns (uint256)
    {
        revert ProposeDisabled();
    }

    /// @notice Always reverts. Use castVoteWithReasonAndParams instead
    function castVote(uint256, uint8) public virtual override returns (uint256) {
        revert CastVoteDisabled();
    }

    /// @notice Always reverts. Use castVoteWithReasonAndParams instead
    function castVoteWithReason(uint256, uint8, string calldata)
        public
        virtual
        override
        returns (uint256)
    {
        revert CastVoteDisabled();
    }

    /// @notice Always reverts. Use castVoteWithReasonAndParamsBySig instead
    function castVoteBySig(uint256, uint8, uint8, bytes32, bytes32)
        public
        virtual
        override
        returns (uint256)
    {
        revert CastVoteDisabled();
    }
}
