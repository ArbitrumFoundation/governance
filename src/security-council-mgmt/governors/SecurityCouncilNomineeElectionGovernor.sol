// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorPreventLateQuorumUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

import "./SecurityCouncilMemberElectionGovernor.sol";

import "../interfaces/ISecurityCouncilManager.sol";
import "./modules/SecurityCouncilNomineeElectionGovernorCountingUpgradeable.sol";
import "./modules/ArbitrumGovernorVotesQuorumFractionUpgradeable.sol";

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
    OwnableUpgradeable
{   
    // todo: these parameters could be reordered to make more sense
    /// @notice parameters for `initialize`
    /// @param targetNomineeCount The target number of nominees to elect (6)
    /// @param firstCohort Cohort of the first election
    /// @param firstNominationStartTime Timestamp of the first election
    /// @param nominationFrequency Delay between elections (expressed in seconds)
    /// @param nomineeVettingDuration Duration of the nominee vetting period (expressed in blocks)
    /// @param nomineeVetter Address of the nominee vetter
    /// @param securityCouncilManager Security council manager contract
    /// @param token Token used for voting
    /// @param owner Owner of the governor
    /// @param quorumNumeratorValue Numerator of the quorum fraction (0.2% = 20)
    /// @param votingPeriod Duration of the voting period (expressed in blocks)
    struct InitParams {
        uint256 targetNomineeCount;
        Cohort firstCohort;
        uint256 firstNominationStartTime;
        uint256 nominationFrequency;
        uint256 nomineeVettingDuration;
        address nomineeVetter;
        ISecurityCouncilManager securityCouncilManager;
        SecurityCouncilMemberElectionGovernor securityCouncilMemberElectionGovernor;
        IVotesUpgradeable token;
        address owner;
        uint256 quorumNumeratorValue;
        uint256 votingPeriod;
    }


    /// @notice The target number of nominees to elect (6)
    uint256 public targetNomineeCount;

    /// @notice Cohort of the first election
    Cohort public firstCohort;

    /// @notice Timestamp of the first election
    uint256 public firstNominationStartTime;

    /// @notice Delay between elections (expressed in seconds)
    uint256 public nominationFrequency;

    /// @notice Duration of the nominee vetting period (expressed in blocks)
    /// @dev    This is the amount of time after voting ends that the nomineeVetter can exclude noncompliant nominees
    uint256 public nomineeVettingDuration;

    /// @notice Address responsible for blocking non compliant nominees
    address public nomineeVetter;

    /// @notice Security council manager contract
    /// @dev    Used to execute the election result immediately if <= 6 compliant nominees are chosen
    ISecurityCouncilManager public securityCouncilManager;

    /// @notice Security council member election governor contract
    SecurityCouncilMemberElectionGovernor public securityCouncilMemberElectionGovernor;

    /// @notice Number of elections created
    uint256 public electionCount;

    /// @notice Contenders up for nomination
    /// @dev    proposalId => contender => bool
    mapping(uint256 => mapping(address => bool)) public contenders;

    /// @notice Excluded nominees for each proposal
    /// @dev    Accounts can only be marked in this mapping if they have received enough votes to be a nominee.
    ///         proposalId => nominee => bool
    mapping(uint256 => mapping(address => bool)) public excluded;

    /// @notice Number of excluded nominees per proposal
    mapping(uint256 => uint256) public excludedNomineeCount;

    event NomineeVetterChanged(address indexed oldNomineeVetter, address indexed newNomineeVetter);
    event ContenderAdded(uint256 indexed proposalId, address indexed contender);
    event NomineeExcluded(uint256 indexed proposalId, address indexed nominee);

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
        _transferOwnership(params.owner);

        targetNomineeCount = params.targetNomineeCount;
        firstCohort = params.firstCohort;
        firstNominationStartTime = params.firstNominationStartTime;
        nominationFrequency = params.nominationFrequency;
        nomineeVettingDuration = params.nomineeVettingDuration;
        nomineeVetter = params.nomineeVetter;
        securityCouncilManager = params.securityCouncilManager;
        securityCouncilMemberElectionGovernor = params.securityCouncilMemberElectionGovernor;
    }

    /// @notice Allows the nominee vetter to call certain functions
    modifier onlyNomineeVetter() {
        require(msg.sender == nomineeVetter, "SecurityCouncilNomineeElectionGovernor: Only the nomineeVetter can call this function");
        _;
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

    /// @notice Always reverts.
    /// @dev    `GovernorUpgradeable` function to create a proposal overridden to just revert. 
    ///         We only want proposals to be created via `createElection`.
    function propose(
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        string memory
    ) public virtual override returns (uint256) {
        revert("SecurityCouncilNomineeElectionGovernor: Proposing is not allowed, call createElection instead");
    }

    /// @notice Normally "the number of votes required in order for a voter to become a proposer." But in our case it is 0.
    /// @dev    Since we only want proposals to be created via `createElection`, we set the proposal threshold to 0.
    ///         `createElection` determines the rules for creating a proposal.
    function proposalThreshold() public view virtual override(GovernorSettingsUpgradeable, GovernorUpgradeable) returns (uint256) {
        return 0;
    }

    /// @notice Creates a new nominee election proposal. 
    ///         Can be called by anyone every `nominationFrequency` seconds.
    /// @return proposalId The id of the proposal
    function createElection() external returns (uint256 proposalId) {
        require(
            block.timestamp >= firstNominationStartTime + nominationFrequency * electionCount, 
            "SecurityCouncilNomineeElectionGovernor: Not enough time has passed since the last election"
        );

        proposalId = GovernorUpgradeable.propose(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            electionIndexToDescription(electionCount)
        );

        electionCount++;
    }

    /// @dev    `GovernorUpgradeable` function to execute a proposal overridden to handle nominee elections.
    ///         Can be called by anyone via `execute` after voting and nominee vetting periods have ended.
    ///         If the number of compliant nominees is > the target number of nominees, 
    ///         we move on to the next phase by calling the SecurityCouncilMemberElectionGovernor.
    ///         If the number of compliant nominees is == the target number of nominees,
    ///         we execute the election result immediately by calling the SecurityCouncilManager.
    ///         If the number of compliant nominees is < the target number of nominees,
    ///         we randomly add some members from the current cohort to the list of nominees and then call the SecurityCouncilManager.
    /// @param  proposalId The id of the proposal
    function _execute(
        uint256 proposalId,
        address[] memory /* targets */,
        uint256[] memory /* values */,
        bytes[] memory /* calldatas */,
        bytes32 /*descriptionHash*/
    ) internal virtual override {
        require(
            block.number > proposalVettingDeadline(proposalId), 
            "SecurityCouncilNomineeElectionGovernor: Proposal is still in the nominee vetting period"
        );

        uint256 compliantNomineeCount = nomineeCount(proposalId) - excludedNomineeCount[proposalId];

        if (compliantNomineeCount > targetNomineeCount) {
            // call the SecurityCouncilMemberElectionGovernor to start the next phase of the election
            securityCouncilMemberElectionGovernor.proposeFromNomineeElectionGovernor();
            return;
        }

        Cohort cohort = electionIndexToCohort(electionCount - 1);
        
        address[] memory maybeCompliantNominees = SecurityCouncilNomineeElectionGovernorCountingUpgradeable.nominees(proposalId);
        address[] memory compliantNominees = SecurityCouncilMgmtUtils.filterAddressesWithExcludeList(
            maybeCompliantNominees, 
            excluded[proposalId]
        );

        if (compliantNominees.length < targetNomineeCount) {
            // there are too few compliant nominees
            // we should randomly select some members from the current cohort to add to the list
            address[] memory currentMembers = cohort == Cohort.SEPTEMBER ? 
                securityCouncilManager.getSeptemberCohort() : securityCouncilManager.getMarchCohort();
            
            compliantNominees = SecurityCouncilMgmtUtils.randomAddToSet({
                pickFrom: currentMembers,
                addTo: compliantNominees,
                targetLength: targetNomineeCount,
                rng: uint256(blockhash(block.number - 1))
            });
        }
        
        // tell the securityCouncilMemberElectionGovernor to call the SecurityCouncilManager to switch out the security council members
        securityCouncilMemberElectionGovernor.executeElectionResult(compliantNominees, cohort);
    }

    /// @notice Put `msg.sender` up for nomination. Must be called before a contender can receive votes.
    /// @dev    Can be called only while a proposal is active (in voting phase)
    ///         A contender cannot be a member of the opposite cohort.
    function addContender(uint256 proposalId) external {
        ProposalState state = state(proposalId);
        require(state == ProposalState.Active, "SecurityCouncilNomineeElectionGovernor: Proposal is not active");

        // check to make sure the contender is not part of the other cohort
        Cohort cohort = electionIndexToCohort(electionCount - 1);

        address[] memory oppositeCohortCurrentMembers = cohort == Cohort.MARCH ? 
            securityCouncilManager.getSeptemberCohort() : securityCouncilManager.getMarchCohort();

        require(
            !SecurityCouncilMgmtUtils.isInArray(msg.sender, oppositeCohortCurrentMembers), 
            "SecurityCouncilNomineeElectionGovernor: Account is a member of the opposite cohort"
        );

        contenders[proposalId][msg.sender] = true;

        emit ContenderAdded(proposalId, msg.sender);
    }

    /// @notice Allows the nomineeVetter to exclude a noncompliant nominee.
    /// @dev    Can be called only after a proposal has succeeded (voting has ended) and before the nominee vetting period has ended.
    ///         Will revert if the provided account is not a nominee (had less than the required votes).
    function excludeNominee(uint256 proposalId, address account) external onlyNomineeVetter {
        require(
            state(proposalId) == ProposalState.Succeeded, 
            "SecurityCouncilNomineeElectionGovernor: Proposal has not succeeded"
        );
        require(
            block.number <= proposalVettingDeadline(proposalId), 
            "SecurityCouncilNomineeElectionGovernor: Proposal is no longer in the nominee vetting period"
        );
        require(
            isNominee(proposalId, account), 
            "SecurityCouncilNomineeElectionGovernor: Account is not a nominee"
        );

        excluded[proposalId][account] = true;
        excludedNomineeCount[proposalId]++;

        emit NomineeExcluded(proposalId, account);
    }

    /// @notice returns true if the account is a nominee for the given proposal and has not been excluded
    /// @param  proposalId The id of the proposal
    /// @param  account The account to check
    function isCompliantNominee(uint256 proposalId, address account) public view returns (bool) {
        return isNominee(proposalId, account) && !excluded[proposalId][account];
    }

    /// @notice returns true if the account is a nominee for the most recent election and has not been excluded
    /// @param  account The account to check
    function isCompliantNomineeForMostRecentElection(address account) external view returns (bool) {
        return isCompliantNominee(electionIndexToProposalId(electionCount - 1), account);
    }

    /// @notice Returns the deadline for the nominee vetting period for a given `proposalId`
    function proposalVettingDeadline(uint256 proposalId) public view returns (uint256) {
        return proposalDeadline(proposalId) + nomineeVettingDuration;
    }

    /// @inheritdoc SecurityCouncilNomineeElectionGovernorCountingUpgradeable
    function _isContender(uint256 proposalId, address possibleContender) internal view virtual override returns (bool) {
        return contenders[proposalId][possibleContender];
    }

    /// @notice Returns the cohort for a given `electionIndex`
    function electionIndexToCohort(uint256 electionIndex) public view returns (Cohort) {
        return Cohort((uint256(firstCohort) + electionIndex) % 2);
    }

    function cohortOfMostRecentElection() external view returns (Cohort) {
        return electionIndexToCohort(electionCount - 1);
    }

    /// @notice Returns the description for a given `electionIndex`
    function electionIndexToDescription(uint256 electionIndex) public pure returns (string memory) {
        return string.concat("Nominee Election #", StringsUpgradeable.toString(electionIndex));
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
}
