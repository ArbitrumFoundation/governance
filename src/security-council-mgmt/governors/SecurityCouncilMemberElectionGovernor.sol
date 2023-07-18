// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./modules/SecurityCouncilMemberElectionGovernorCountingUpgradeable.sol";
import "./SecurityCouncilNomineeElectionGovernor.sol";

/// @title  SecurityCouncilMemberElectionGovernor
/// @notice Narrows a set of nominees down to a set of members.
/// @dev    Proposals are created by the SecurityCouncilNomineeElectionGovernor.
///         This governor is responsible for executing the final election result by calling the SecurityCouncilManager.
contract SecurityCouncilMemberElectionGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorVotesUpgradeable,
    SecurityCouncilMemberElectionGovernorCountingUpgradeable,
    GovernorSettingsUpgradeable,
    OwnableUpgradeable
{
    /// @notice The SecurityCouncilNomineeElectionGovernor that creates proposals for this governor and contains the list of compliant nominees
    SecurityCouncilNomineeElectionGovernor public nomineeElectionGovernor;

    /// @notice The SecurityCouncilManager that will execute the election result
    ISecurityCouncilManager public securityCouncilManager;

    error InvalidDurations(uint256 fullWeightDuration, uint256 votingPeriod);
    error OnlyNomineeElectionGovernor();
    error ProposeDisabled();

    /// @param _nomineeElectionGovernor The SecurityCouncilNomineeElectionGovernor
    /// @param _securityCouncilManager The SecurityCouncilManager
    /// @param _token The token used for voting
    /// @param _owner The owner of the governor
    /// @param _votingPeriod The duration of voting on a proposal
    /// @param _fullWeightDuration Duration of full weight voting (blocks)
    function initialize(
        SecurityCouncilNomineeElectionGovernor _nomineeElectionGovernor,
        ISecurityCouncilManager _securityCouncilManager,
        IVotesUpgradeable _token,
        address _owner,
        uint256 _votingPeriod,
        uint256 _fullWeightDuration
    ) public initializer {
        if (_fullWeightDuration > _votingPeriod) {
            revert InvalidDurations(_fullWeightDuration, _votingPeriod);
        }

        __Governor_init("SecurityCouncilMemberElectionGovernor");
        __GovernorVotes_init(_token);
        __SecurityCouncilMemberElectionGovernorCounting_init({
            initialFullWeightDuration: _fullWeightDuration
        });
        __GovernorSettings_init(0, _votingPeriod, 0);
        _transferOwnership(_owner);

        nomineeElectionGovernor = _nomineeElectionGovernor;
        securityCouncilManager = _securityCouncilManager;
    }

    modifier onlyNomineeElectionGovernor() {
        if (msg.sender != address(nomineeElectionGovernor)) {
            revert OnlyNomineeElectionGovernor();
        }
        _;
    }

    /**
     * permissioned state mutating functions *************
     */

    /// @notice Creates a new member election proposal from the most recent nominee election.
    function proposeFromNomineeElectionGovernor() external onlyNomineeElectionGovernor {
        GovernorUpgradeable.propose(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            nomineeElectionGovernor.electionIndexToDescription(
                nomineeElectionGovernor.electionCount() - 1
            )
        );
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

    /**
     * internal/private state mutating functions *************
     */

    /// @dev    `GovernorUpgradeable` function to execute a proposal overridden to handle nominee elections.
    ///         We know that _getTopNominees will return a full list of nominees because we checked it in _voteSucceeded.
    ///         Calls `SecurityCouncilManager.replaceCohort` with the list of nominees.
    function _execute(
        uint256 proposalId,
        address[] memory, /* targets */
        uint256[] memory, /* values */
        bytes[] memory, /* calldatas */
        bytes32 /* descriptionHash */
    ) internal override {
        // we know that the list is full because we checked it in _voteSucceeded
        securityCouncilManager.replaceCohort({
            _newCohort: topNominees(proposalId),
            _cohort: nomineeElectionGovernor.currentCohort()
        });
    }

    /**
     * view/pure functions *************
     */

    /// @notice Normally "the number of votes required in order for a voter to become a proposer." But in our case it is 0.
    /// @dev    Since we only want proposals to be created via `proposeFromNomineeElectionGovernor`, we set the proposal threshold to 0.
    ///         `proposeFromNomineeElectionGovernor` determines the rules for creating a proposal.
    function proposalThreshold()
        public
        pure
        override(GovernorSettingsUpgradeable, GovernorUpgradeable)
        returns (uint256)
    {
        return 0;
    }

    /// @notice Quorum is always 0.
    function quorum(uint256) public pure override returns (uint256) {
        return 0;
    }

    /**
     * internal view/pure functions *************
     */

    /// @dev returns true if the account is a compliant nominee.
    ///      checks the SecurityCouncilNomineeElectionGovernor to see if the account is a compliant nominee
    function _isCompliantNominee(uint256 proposalId, address possibleNominee)
        internal
        view
        override
        returns (bool)
    {
        return nomineeElectionGovernor.isCompliantNominee(proposalId, possibleNominee);
    }

    // CHRIS: TODO: docs
    function _compliantNominees(uint256 proposalId)
        internal
        view
        override
        returns (address[] memory)
    {
        return nomineeElectionGovernor.compliantNominees(proposalId);
    }

    /// @inheritdoc SecurityCouncilMemberElectionGovernorCountingUpgradeable
    function _targetMemberCount() internal view override returns (uint256) {
        return securityCouncilManager.cohortSize();
    }

    /**
     * disabled functions *************
     */

    /// @notice Always reverts.
    /// @dev    `GovernorUpgradeable` function to create a proposal overridden to just revert.
    ///         We only want proposals to be created via `proposeFromNomineeElectionGovernor`.
    function propose(address[] memory, uint256[] memory, bytes[] memory, string memory)
        public
        virtual
        override
        returns (uint256)
    {
        revert ProposeDisabled();
    }
}
