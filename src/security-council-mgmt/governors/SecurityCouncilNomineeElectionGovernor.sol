// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorPreventLateQuorumUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

import "../interfaces/ISecurityCouncilManager.sol";
import "./modules/SecurityCouncilNomineeElectionGovernorCountingUpgradeable.sol";
import "./modules/ArbitrumGovernorVotesQuorumFractionUpgradeable.sol";

import "../SecurityCouncilMgmtUtils.sol";

// handles phase 1 of security council elections (narrowing contenders down to a set of nominees)
// note: this contract assumes that there can only be one proposalId with state Active or Succeeded at a time 
// (easy to override state() to return `Expired` if they succeeded but haven't executed after some time)
contract SecurityCouncilNomineeElectionGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorVotesUpgradeable,
    SecurityCouncilNomineeElectionGovernorCountingUpgradeable,
    ArbitrumGovernorVotesQuorumFractionUpgradeable,
    GovernorSettingsUpgradeable,
    OwnableUpgradeable
{
    /// @notice The target number of nominees to elect (6)
    uint256 public targetNomineeCount;

    /// @notice Cohort of the first election
    Cohort public firstCohort;

    /// @notice Timestamp of the first election
    uint256 public firstNominationStartTime;

    /// @notice Delay between elections (expressed in seconds)
    uint256 public nominationFrequency;

    /// @notice Duration of the blacklist / nominee vetting period (expressed in blocks)
    /// @dev    This is the amount of time after voting ends that the nomineeVetter can blacklist noncompliant nominees
    uint256 public nomineeVettingDuration;

    /// @notice Address responsible for blocking non compliant nominees
    address public nomineeVetter;

    /// @notice Security council manager contract
    /// @dev    Used to execute the election result immediately if <= 6 compliant nominees are chosen
    ISecurityCouncilManager public securityCouncilManager;

    /// @notice Number of proposals created
    uint256 public proposalCount;

    /// @notice Contenders up for nomination
    /// @dev    proposalId => contender => bool
    mapping(uint256 => mapping(address => bool)) public contenders;

    /// @notice Blacklisted nominees per proposal
    /// @dev    Accounts can only be marked in this mapping if they have received enough votes to be a nominee.
    ///         proposalId => nominee => bool
    mapping(uint256 => mapping(address => bool)) public blacklisted;

    /// @notice Number of blacklisted nominees per proposal
    mapping(uint256 => uint256) public blacklistedNomineeCount;

    constructor() {
        _disableInitializers();
    }

    // todo: these parameters could be reordered to make more sense
    /// @param _targetNomineeCount The target number of nominees to elect (6)
    /// @param _firstCohort Cohort of the first election
    /// @param _firstNominationStartTime Timestamp of the first election
    /// @param _nominationFrequency Delay between elections (expressed in seconds)
    /// @param _nomineeVettingDuration Duration of the blacklist period (expressed in blocks)
    /// @param _nomineeVetter Address of the nominee vetter
    /// @param _securityCouncilManager Security council manager contract
    /// @param _token Token used for voting
    /// @param _owner Owner of the governor
    /// @param _quorumNumeratorValue Numerator of the quorum fraction (0.2% = 20)
    /// @param _votingDelay Delay before voting starts (expressed in blocks)
    /// @param _votingPeriod Duration of the voting period (expressed in blocks)
    function initialize(
        uint256 _targetNomineeCount,
        Cohort _firstCohort,
        uint256 _firstNominationStartTime,
        uint256 _nominationFrequency,
        uint256 _nomineeVettingDuration,
        address _nomineeVetter,
        ISecurityCouncilManager _securityCouncilManager,
        IVotesUpgradeable _token,
        address _owner,
        uint256 _quorumNumeratorValue,
        uint256 _votingDelay,
        uint256 _votingPeriod
    ) public initializer {
        __Governor_init("Security Council Nominee Election Governor");
        __GovernorVotes_init(_token);
        __SecurityCouncilNomineeElectionGovernorCounting_init();
        __ArbitrumGovernorVotesQuorumFraction_init(_quorumNumeratorValue);
        __GovernorSettings_init(_votingDelay, _votingPeriod, 0);
        _transferOwnership(_owner);

        targetNomineeCount = _targetNomineeCount;
        firstCohort = _firstCohort;
        firstNominationStartTime = _firstNominationStartTime;
        nominationFrequency = _nominationFrequency;
        nomineeVettingDuration = _nomineeVettingDuration;
        nomineeVetter = _nomineeVetter;
        securityCouncilManager = _securityCouncilManager;
    }

    /// @notice Allows the nominee vetter to call certain functions
    modifier onlyNomineeVetter() {
        require(msg.sender == nomineeVetter, "Only the nomineeVetter can call this function");
        _;
    }

    /// @notice Allows the owner to change the nomineeVetter
    function setNomineeVetter(address _nomineeVetter) external onlyOwner {
        nomineeVetter = _nomineeVetter;
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
        revert("Proposing is not allowed, call createElection instead");
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
        require(block.timestamp >= firstNominationStartTime + nominationFrequency * proposalCount, "Not enough time has passed since the last election");

        proposalId = GovernorUpgradeable.propose(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            proposalIndexToDescription(proposalCount)
        );

        proposalCount++;
    }

    /// @dev    `GovernorUpgradeable` function to execute a proposal overridden to handle nominee elections.
    ///         Can be called by anyone via `execute` after voting and blacklisting periods have ended.
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
        require(block.number > proposalVettingDeadline(proposalId), "Proposal is still in the nominee vetting period");

        uint256 compliantNomineeCount = nomineeCount(proposalId) - blacklistedNomineeCount[proposalId];

        if (compliantNomineeCount > targetNomineeCount) {
            // todo:
            // call the SecurityCouncilMemberElectionGovernor to execute the election
            // the SecurityCouncilMemberElectionGovernor will call back into this contract to look up nominees
            return;
        }

        Cohort cohort = proposalIndexToCohort(proposalCount - 1);
        
        address[] memory maybeCompliantNominees = SecurityCouncilNomineeElectionGovernorCountingUpgradeable.nominees(proposalId);
        address[] memory compliantNominees = SecurityCouncilMgmtUtils.filterAddressesWithBlacklist(maybeCompliantNominees, blacklisted[proposalId]);

        if (compliantNominees.length < targetNomineeCount) {
            // there are too few compliant nominees
            // we should randomly select some members from the current cohort to add to the list
            address[] memory currentMembers = cohort == Cohort.SEPTEMBER ? securityCouncilManager.getSeptemberCohort() : securityCouncilManager.getMarchCohort();
            compliantNominees = SecurityCouncilMgmtUtils.randomAddToSet(currentMembers, compliantNominees, targetNomineeCount, uint256(blockhash(block.number - 1)));
        }
        
        // call the SecurityCouncilManager to switch out the security council members
        securityCouncilManager.executeElectionResult(compliantNominees, cohort);
    }

    /// @notice Put up a contender for nomination. Must be called before a contender can receive votes.
    /// @dev    Can be called only while a proposal is active (in voting phase)
    ///         A contender cannot be a member of the opposite cohort.
    function addContender(uint256 proposalId, address account) external {
        ProposalState state = state(proposalId);
        require(state == ProposalState.Active, "Proposal is not active");

        // check to make sure the contender is not part of the other cohort
        Cohort cohort = proposalIndexToCohort(proposalCount - 1);
        address[] memory oppositeCohortCurrentMembers = cohort == Cohort.MARCH ? securityCouncilManager.getSeptemberCohort() : securityCouncilManager.getMarchCohort();
        require(!SecurityCouncilMgmtUtils.isInArray(account, oppositeCohortCurrentMembers), "Account is a member of the opposite cohort");

        contenders[proposalId][account] = true;
    }

    /// @notice Allows the nomineeVetter to blacklist a noncompliant nominee.
    /// @dev    Can be called only after a proposal has succeeded (voting has ended) and before the nominee vetting period has ended.
    ///         Will revert if the provided account is not a nominee (had less than the required votes).
    function blacklistNominee(uint256 proposalId, address account) external onlyNomineeVetter {
        require(state(proposalId) == ProposalState.Succeeded, "Proposal has not succeeded");
        require(block.number <= proposalVettingDeadline(proposalId), "Proposal is no longer in the nominee vetting period");
        require(isNominee(proposalId, account), "Account is not a nominee");
        blacklisted[proposalId][account] = true;
        blacklistedNomineeCount[proposalId]++;
    }

    /// @notice returns true if the account is a nominee and has not been blacklisted
    /// @param  proposalId The id of the proposal
    /// @param  account The account to check
    function isCompliantNominee(uint256 proposalId, address account) external view returns (bool) {
        return isNominee(proposalId, account) && !blacklisted[proposalId][account];
    }

    /// @notice Returns the deadline for the nominee vetting period for a given `proposalId`
    function proposalVettingDeadline(uint256 proposalId) public view returns (uint256) {
        return proposalDeadline(proposalId) + nomineeVettingDuration;
    }

    /// @inheritdoc SecurityCouncilNomineeElectionGovernorCountingUpgradeable
    function _isContender(uint256 proposalId, address contender) internal view virtual override returns (bool) {
        return contenders[proposalId][contender];
    }

    /// @notice Returns the cohort for a given `proposalIndex`
    function proposalIndexToCohort(uint256 proposalIndex) public view returns (Cohort) {
        return Cohort((uint256(firstCohort) + proposalIndex) % 2);
    }

    /// @notice Returns the description for a given `proposalIndex`
    function proposalIndexToDescription(uint256 proposalIndex) public pure returns (string memory) {
        return string.concat("Nominee Election #", StringsUpgradeable.toString(proposalIndex));
    }

    /// @notice Returns the proposalId for a given `proposalIndex`
    function proposalIndexToProposalId(uint256 proposalIndex) public pure returns (uint256) {
        return hashProposal(
            new address[](1), 
            new uint256[](1),
            new bytes[](1),
            keccak256(bytes(proposalIndexToDescription(proposalIndex)))
        );
    }
}
