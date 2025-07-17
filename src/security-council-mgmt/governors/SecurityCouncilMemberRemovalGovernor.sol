// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorPreventLateQuorumUpgradeable.sol";
import
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./../interfaces/ISecurityCouncilManager.sol";
import "../Common.sol";
import "./modules/ArbitrumGovernorVotesQuorumFractionUpgradeable.sol";
import "./modules/ArbitrumGovernorProposalExpirationUpgradeable.sol";

/// @title SecurityCouncilMemberRemovalGovernor
/// @notice Allows the DAO to remove a security council member
contract SecurityCouncilMemberRemovalGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorVotesUpgradeable,
    GovernorPreventLateQuorumUpgradeable,
    GovernorCountingSimpleUpgradeable,
    ArbitrumGovernorVotesQuorumFractionUpgradeable,
    GovernorSettingsUpgradeable,
    ArbitrumGovernorProposalExpirationUpgradeable,
    OwnableUpgradeable
{
    uint256 public constant VOTE_SUCCESS_DENOMINATOR = 10_000;
    uint256 public voteSuccessNumerator;
    ISecurityCouncilManager public securityCouncilManager;

    event VoteSuccessNumeratorSet(uint256 indexed voteSuccessNumerator);
    event MemberRemovalProposed(address memberToRemove, string description);

    error InvalidOperationsLength(uint256 len);
    error TargetNotManager(address target);
    error ValueNotZero(uint256 value);
    error UnexpectedCalldataLength(uint256 len);
    error CallNotRemoveMember(bytes4 selector, bytes4 expectedSelector);
    error MemberNotFound(address memberToRemove);
    error AbstainDisallowed();
    error InvalidVoteSuccessNumerator(uint256 voteSuccessNumerator);

    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract
    /// @param _voteSuccessNumerator value that with denominator 10_000 determines the ration of for/against votes required for success
    /// @param _securityCouncilManager security council manager contract
    /// @param _token The address of the governance token
    /// @param _owner The DAO (Upgrade Executor); admin over proposal role
    /// @param _votingDelay The delay between a proposal submission and voting starts
    /// @param _votingPeriod The period for which the vote lasts
    /// @param _quorumNumerator The proportion of the circulating supply required to reach a quorum
    /// @param _proposalThreshold The number of delegated votes required to create a proposal
    /// @param _minPeriodAfterQuorum The minimum number of blocks available for voting after the quorum is reached
    function initialize(
        uint256 _voteSuccessNumerator,
        ISecurityCouncilManager _securityCouncilManager,
        IVotesUpgradeable _token,
        address _owner,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumNumerator,
        uint256 _proposalThreshold,
        uint64 _minPeriodAfterQuorum,
        uint256 _proposalExpirationBlocks
    ) public initializer {
        __Governor_init("SecurityCouncilMemberRemovalGovernor");
        __GovernorSettings_init(_votingDelay, _votingPeriod, _proposalThreshold);
        __GovernorCountingSimple_init();
        __GovernorVotes_init(_token);
        __ArbitrumGovernorVotesQuorumFraction_init(_quorumNumerator);
        __GovernorPreventLateQuorum_init(_minPeriodAfterQuorum);
        __ArbitrumGovernorProposalExpirationUpgradeable_init(_proposalExpirationBlocks);
        _transferOwnership(_owner);

        if (!Address.isContract(address(_securityCouncilManager))) {
            revert NotAContract(address(_securityCouncilManager));
        }

        securityCouncilManager = _securityCouncilManager;
        _setVoteSuccessNumerator(_voteSuccessNumerator);
    }

    /// @notice Assumes the passed in bytes is an abi encoded function call, and splits into the selector and the rest
    /// @param calldataWithSelector The call data to split
    /// @return The selector
    /// @return The rest of the function call data
    function separateSelector(bytes calldata calldataWithSelector)
        external
        pure
        returns (bytes4, bytes memory)
    {
        bytes4 selector = bytes4(calldataWithSelector[:4]);
        bytes memory rest = calldataWithSelector[4:];
        return (selector, rest);
    }

    /// @notice Propose a security council member removal. Method conforms to the governor propose interface
    ///         but enforces that only calls to securityCouncilManager's removeMember can be proposed.
    /// @param targets Target contract operation; must be [securityCouncilManager]
    /// @param values Value for removeMember; must be [0]
    /// @param calldatas Operation calldata; must be [removeMember with address argument]
    /// @param description rationale for member removal
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256) {
        if (targets.length != 1) {
            revert InvalidOperationsLength(targets.length);
        }
        // length equality of targets, values, and calldatas is checked in  GovernorUpgradeable.propose

        if (targets[0] != address(securityCouncilManager)) {
            revert TargetNotManager(targets[0]);
        }
        if (values[0] != 0) {
            revert ValueNotZero(values[0]);
        }
        // selector + 1 word to hold the address
        if (calldatas[0].length != 36) {
            revert UnexpectedCalldataLength(calldatas[0].length);
        }

        (bytes4 selector, bytes memory rest) = this.separateSelector(calldatas[0]);
        if (selector != ISecurityCouncilManager.removeMember.selector) {
            revert CallNotRemoveMember(selector, ISecurityCouncilManager.removeMember.selector);
        }

        address memberToRemove = abi.decode(rest, (address));
        if (
            !securityCouncilManager.firstCohortIncludes(memberToRemove)
                && !securityCouncilManager.secondCohortIncludes(memberToRemove)
        ) {
            revert MemberNotFound(memberToRemove);
        }

        emit MemberRemovalProposed(memberToRemove, description);
        return GovernorUpgradeable.propose(targets, values, calldatas, description);
    }

    /// @notice override to allow for required vote success ratio that isn't 0.5
    /// @param proposalId target proposal id
    function _voteSucceeded(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorCountingSimpleUpgradeable, GovernorUpgradeable)
        returns (bool)
    {
        (uint256 againstVotes, uint256 forVotes,) = proposalVotes(proposalId);

        // for-votes / total-votes  >=  success-numerator/ success-denominator
        return
            VOTE_SUCCESS_DENOMINATOR * forVotes >= (forVotes + againstVotes) * voteSuccessNumerator;
    }

    /// @notice A removal proposal if a threshold of all cast votes vote in favor of removal.
    ///         Thus, abstaining would be exactly equivalent to voting against.
    ///         To prevent any confusion, abstaining is disallowed.
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory params
    ) internal virtual override(GovernorCountingSimpleUpgradeable, GovernorUpgradeable) {
        if (VoteType(support) == VoteType.Abstain) {
            revert AbstainDisallowed();
        }
        GovernorCountingSimpleUpgradeable._countVote(proposalId, account, support, weight, params);
    }

    /// @notice Set numerator for removal vote to succeed; only DAO can call
    /// @param _voteSuccessNumerator new numerator value
    function setVoteSuccessNumerator(uint256 _voteSuccessNumerator) public onlyOwner {
        _setVoteSuccessNumerator(_voteSuccessNumerator);
    }

    function _setVoteSuccessNumerator(uint256 _voteSuccessNumerator) internal {
        if (!(0 < _voteSuccessNumerator && _voteSuccessNumerator <= VOTE_SUCCESS_DENOMINATOR)) {
            revert InvalidVoteSuccessNumerator(_voteSuccessNumerator);
        }
        voteSuccessNumerator = _voteSuccessNumerator;
        emit VoteSuccessNumeratorSet(_voteSuccessNumerator);
    }

    /// @inheritdoc IGovernorUpgradeable
    function COUNTING_MODE()
        public
        pure
        virtual
        override(GovernorCountingSimpleUpgradeable, IGovernorUpgradeable)
        returns (string memory)
    {
        return "support=for,against&quorum=for";
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

    /// @inheritdoc GovernorUpgradeable
    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return GovernorSettingsUpgradeable.proposalThreshold();
    }

    /// @inheritdoc GovernorPreventLateQuorumUpgradeable
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    )
        internal
        override(GovernorUpgradeable, GovernorPreventLateQuorumUpgradeable)
        returns (uint256)
    {
        return GovernorPreventLateQuorumUpgradeable._castVote(
            proposalId, account, support, reason, params
        );
    }

    /// @inheritdoc GovernorPreventLateQuorumUpgradeable
    function proposalDeadline(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorPreventLateQuorumUpgradeable)
        returns (uint256)
    {
        return GovernorPreventLateQuorumUpgradeable.proposalDeadline(proposalId);
    }

    function state(uint256 proposalId)
        public
        view
        override(ArbitrumGovernorProposalExpirationUpgradeable, GovernorUpgradeable)
        returns (ProposalState)
    {
        // We override the state to transition to expire unexecuted proposals
        // This is because of potential race conditions between the removal governor and other
        // parties (normal elections + security council) calling the other functions on the security council manager
        // The manager does some checks to ensure that the removal can occur (eg the account is a member) - if these checks fail
        // then the proposal in here will fail. If this is the case we want the proposal to expire
        // after some time so that it doesnt become executable (in an unexpected way) far in the future due
        // to normal changes in the security council membership.
        return ArbitrumGovernorProposalExpirationUpgradeable.state(proposalId);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;
}
