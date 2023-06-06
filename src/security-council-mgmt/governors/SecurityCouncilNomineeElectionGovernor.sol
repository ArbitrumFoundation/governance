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

// handles phase 1 of security council elections (narrowing contenders down to a set of nominees)
contract SecurityCouncilNomineeElectionGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorVotesUpgradeable,
    SecurityCouncilNomineeElectionGovernorCountingUpgradeable,
    ArbitrumGovernorVotesQuorumFractionUpgradeable,
    GovernorSettingsUpgradeable,
    OwnableUpgradeable
{
    uint256 public targetNomineeCount;
    Cohort public firstCohort;
    uint256 public firstNominationStartTime;
    uint256 public nominationFrequency;
    // delay between voting end and when execute can be called (expressed in blocks)
    // this allows the foundation to blacklist noncompliant nominees
    uint256 public foundationBlacklistDuration;
    address public foundation;
    ISecurityCouncilManager public securityCouncilManager;

    // number of nominee elections that have been created
    uint256 public proposalCount;

    // maps proposalId to map of address to bool indicating whether the account is a contender for nomination
    mapping(uint256 => mapping(address => bool)) public contenders;

    // proposalId => nominee => bool indicating whether the nominee has been blacklisted
    mapping(uint256 => mapping(address => bool)) public blacklisted;

    // proposalId => blacklisted nominee count
    mapping(uint256 => uint256) public blacklistedNomineeCount;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _targetNomineeCount,
        Cohort _firstCohort,
        uint256 _firstNominationStartTime,
        uint256 _nominationFrequency,
        uint256 _foundationBlacklistDuration,
        address _foundation,
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
        foundationBlacklistDuration = _foundationBlacklistDuration;
        foundation = _foundation;
        securityCouncilManager = _securityCouncilManager;
    }


    modifier onlyFoundation {
        require(msg.sender == foundation, "Only the foundation can call this function");
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
        revert("Proposing is not allowed, call createElection instead");
    }

    // proposal threshold is 0 because we call propose via createElection
    function proposalThreshold() public view virtual override(GovernorSettingsUpgradeable, GovernorUpgradeable) returns (uint256) {
        return 0;
    }

    function createElection() external returns (uint256 proposalIndex, uint256 proposalId) {
        require(block.timestamp >= firstNominationStartTime + nominationFrequency * proposalCount, "Not enough time has passed since the last election");

        // create a proposal with dummy address and value
        // make the calldata abi.encode(proposalIndex)
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
        uint256 proposalId,
        address[] memory /* targets */,
        uint256[] memory /* values */,
        bytes[] memory calldatas,
        bytes32 /*descriptionHash*/
    ) internal virtual override {
        uint256 blacklistDeadline = proposalDeadline(proposalId) + foundationBlacklistDuration;
        require(block.number > blacklistDeadline, "Proposal is still in the blacklist period");

        uint256 numBlacklisted = blacklistedNomineeCount[proposalId];
        uint256 numNominated = nomineeCount(proposalId) - numBlacklisted;

        if (numNominated > targetNomineeCount) {
            // todo:
            // call the SecurityCouncilMemberElectionGovernor to execute the election
            // the SecurityCouncilMemberElectionGovernor will call back into this contract to look up nominees
            return;
        }

        address[] memory nominees;
        if (numNominated < targetNomineeCount) {
            // todo: randomly select some number of members from current cohort to add to the nominees
            // nominees = ...
        }
        else if (numBlacklisted > 0) {
            // there are exactly the right number of compliant nominees
            // but some of the nominees have been blacklisted
            // we should remove the blacklisted nominees from SecurityCouncilNomineeElectionGovernorCounting's list
            address[] memory maybeCompliantNominees = SecurityCouncilNomineeElectionGovernorCountingUpgradeable.nominees(proposalId);
            nominees = new address[](targetNomineeCount);

            uint256 j = 0;
            for (uint256 i = 0; i < maybeCompliantNominees.length; i++) {
                address nominee = maybeCompliantNominees[i];
                if (!blacklisted[proposalId][nominee]) {
                    nominees[j] = nominee;
                    j++;
                }
            }
        }
        else {
            // there are exactly the right number of compliant nominees and none have been blacklisted
            nominees = SecurityCouncilNomineeElectionGovernorCountingUpgradeable.nominees(proposalId);
        }
        
        // call the SecurityCouncilManager to switch out the security council members
        uint256 proposalIndex = abi.decode(calldatas[0], (uint256));
        securityCouncilManager.executeElectionResult(nominees, proposalIndexToCohort(proposalIndex));
    }

    function addContender(uint256 proposalId, address account) external {
        ProposalState state = state(proposalId);
        require(state == ProposalState.Active, "Proposal is not active");

        // todo: check to make sure the contender is eligible (not part of the other cohort, etc.)

        contenders[proposalId][account] = true;
    }

    function blacklistNominee(uint256 proposalId, address account) external onlyFoundation {
        // todo: during what state(s) should this be allowed? ProposalState.Succeeded? ProposalState.Active or ProposalState.Succeeded?
        // if this is allowed during ProposalState.Active, then SecurityCouncilNomineeElectionGovernorCounting should revert when someone tries to cast a vote for a blacklisted contender
        blacklisted[proposalId][account] = true;
        blacklistedNomineeCount[proposalId]++;
    }

    // phase 2&3 governor calls this to check whether a nominee is compliant and can receive votes
    function isCompliantNominee(uint256 proposalId, address account) external view returns (bool) {
        return isNominee(proposalId, account) && !blacklisted[proposalId][account];
    }

    function _isContender(uint256 proposalId, address contender) internal view virtual override returns (bool) {
        return contenders[proposalId][contender];
    }

    function proposalIndexToCohort(uint256 proposalIndex) public view returns (Cohort) {
        return Cohort((uint256(firstCohort) + proposalIndex) % 2);
    }

    function proposalIndexToDescription(uint256 proposalIndex) public pure returns (string memory) {
        return string.concat("Nominee Election #", StringsUpgradeable.toString(proposalIndex));
    }

    function proposalIndexToProposalId(uint256 proposalIndex) public pure returns (uint256) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encode(proposalIndex);

        return hashProposal(targets, values, calldatas, keccak256(bytes(proposalIndexToDescription(proposalIndex))));
    }
}
