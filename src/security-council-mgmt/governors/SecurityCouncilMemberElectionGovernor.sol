// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

import "./modules/ArbitrumGovernorVotesQuorumFractionUpgradeable.sol";
import "./modules/SecurityCouncilMemberElectionGovernorCountingUpgradeable.sol";
import "./SecurityCouncilNomineeElectionGovernor.sol";

import "../SecurityCouncilManager.sol";


// narrows a set of nominees to a set of 6 members
// proposals are created by the NomineeElectionGovernor
// this contract assumes that any active proposal corresponds to the last NomineeElectionGovernor election
// we may want to override state() such that a successful proposal expires if it isn't executed after some time
contract SecurityCouncilMemberElectionGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorVotesUpgradeable,
    SecurityCouncilMemberElectionGovernorCountingUpgradeable,
    GovernorSettingsUpgradeable,
    OwnableUpgradeable
{
    SecurityCouncilNomineeElectionGovernor public nomineeElectionGovernor;
    SecurityCouncilManager public securityCouncilManager;

    function initialize(
        SecurityCouncilNomineeElectionGovernor _nomineeElectionGovernor,
        SecurityCouncilManager _securityCouncilManager,
        IVotesUpgradeable _token,
        address _owner,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _maxNominees,
        uint256 _fullWeightDurationNumerator,
        uint256 _decreasingWeightDurationNumerator,
        uint256 _durationDenominator
    ) public initializer {
        __Governor_init("SecurityCouncilMemberElectionGovernor");
        __GovernorVotes_init(_token);
        __SecurityCouncilMemberElectionGovernorCounting_init({
            _maxNominees: _maxNominees,
            _fullWeightDurationNumerator: _fullWeightDurationNumerator,
            _decreasingWeightDurationNumerator: _decreasingWeightDurationNumerator,
            _durationDenominator: _durationDenominator
        });
        __GovernorSettings_init(_votingDelay, _votingPeriod, 0);
        _transferOwnership(_owner);

        nomineeElectionGovernor = _nomineeElectionGovernor;
        securityCouncilManager = _securityCouncilManager;
    }

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

    function quorum(uint256) public pure override returns (uint256) {
        return 0;
    }

    function proposeFromNomineeElectionGovernor() external onlyNomineeElectionGovernor {
        GovernorUpgradeable.propose(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            nomineeElectionIndexToDescription(nomineeElectionGovernor.electionCount() - 1)
        );
    }

    function _execute(
        uint256 proposalId,
        address[] memory /* targets */,
        uint256[] memory /* values */,
        bytes[] memory /* calldatas */,
        bytes32 /* descriptionHash */
    ) internal override {
        // we know that the list is full because we checked it in _voteSucceeded
        securityCouncilManager.executeElectionResult({
            _newCohort: _getTopNominees(proposalId),
            _cohort: nomineeElectionGovernor.cohortOfMostRecentElection()
        });
    }

    function nomineeElectionIndexToDescription(uint256 electionIndex) public pure returns (string memory) {
        return string.concat("Member Election for Nominee Election #", StringsUpgradeable.toString(electionIndex));
    }

    /// @dev returns true if the nominee is compliant
    ///      checks the SecurityCouncilNomineeElectionGovernor to see if the account is a compliant nominee of the most recent nominee election
    function _isCompliantNomineeForMostRecentElection(address nominee) internal view override returns (bool) {
        return nomineeElectionGovernor.isCompliantNomineeForMostRecentElection(nominee);
    }
}