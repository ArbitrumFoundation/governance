// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {L2ArbitrumGovernor} from "../L2ArbitrumGovernor.sol";
import {
    IVotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {
    GovernorUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {
    IGovernorUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {TimersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/TimersUpgradeable.sol";
import {IVotingTokenMirror} from "./VotingTokenMirror.sol";

/// @title  L1ArbitrumGovernor
/// @notice Governor for the Arbitrum DAO's L1 voting system. Sources voting power from a
///         VotingTokenMirror backed by L2 ARB delegation proven against confirmed assertions.
/// @dev    An additional {propose} function is provided to allow proposers to specify a threshold
///         block up to {maxProposalBlockLookback} blocks old. A function is also provided to reset
///         a proposal's snapshot block to a new block within the voting period. These two
///         functions allow delegates to fix the snapshots to blocks with known checkpoints in
///         the L2 state mirror.
///         
///         Inherited doc comments saying a lookup "returns 0" may not apply here: the
///         VotingTokenMirror reverts on zero/unproven values instead of returning 0.
///
///         Since {state} depends on quorum, which depends on values being proven in the
///         L2 state mirror, {state} may revert if the necessary values are not yet proven.
///         If the necessary values are never proven, {state} will revert forever.
contract L1ArbitrumGovernor is L2ArbitrumGovernor {
    using TimersUpgradeable for TimersUpgradeable.BlockNumber;

    /// @notice Max age in blocks of the threshold block named in {propose}.
    uint256 public maxProposalBlockLookback;

    /// @notice Whether a proposal's snapshot has been locked by {lockProposalSnapshot}.
    mapping(uint256 => bool) public proposalSnapshotLocked;

    /// @dev Set only for the duration of a 5-arg {propose} call; redirects {getVotes} so the
    ///      base governor's proposer threshold check uses the chosen block. Transient storage is
    ///      unavailable in this compiler version, so we use regular storage for simplicity.
    uint256 private _thresholdBlockOverride;

    event ProposalSnapshotLocked(uint256 indexed proposalId, uint256 blockNumber);

    /// @dev The L2 initializer lacks min/max quorum; use the overload below instead.
    function initialize(
        IVotesUpgradeable,
        TimelockControllerUpgradeable,
        address,
        uint256,
        uint256,
        uint256,
        uint256,
        uint64
    ) external pure override {
        revert("L1ArbitrumGovernor: WRONG_INITIALIZER");
    }

    /// @dev Copied from L2ArbitrumGovernor.initialize but with the addition of min and max quorum
    ///      since that was added after the initial L2 governor deployment, plus maxProposalBlockLookback.
    function initialize(
        IVotesUpgradeable _token,
        TimelockControllerUpgradeable _timelock,
        address _owner,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumNumerator,
        uint256 _proposalThreshold,
        uint64 _minPeriodAfterQuorum,
        uint256 _minimumQuorum,
        uint256 _maximumQuorum,
        uint256 _maxProposalBlockLookback
    ) external initializer {
        __Governor_init("L1ArbitrumGovernor");
        __GovernorSettings_init(_votingDelay, _votingPeriod, _proposalThreshold);
        __GovernorCountingSimple_init();
        __GovernorVotes_init(_token);
        __GovernorTimelockControl_init(_timelock);
        __GovernorVotesQuorumFraction_init(_quorumNumerator);
        __GovernorPreventLateQuorum_init(_minPeriodAfterQuorum);
        _transferOwnership(_owner);
        _setQuorumMinAndMax(_minimumQuorum, _maximumQuorum);
        _setMaxProposalBlockLookback(_maxProposalBlockLookback);
    }

    /// @notice Set the max age in blocks of the threshold block named in {propose}
    function setMaxProposalBlockLookback(uint256 _maxProposalBlockLookback)
        external
        onlyGovernance
    {
        _setMaxProposalBlockLookback(_maxProposalBlockLookback);
    }

    function _setMaxProposalBlockLookback(uint256 _maxProposalBlockLookback) internal {
        require(_maxProposalBlockLookback > 0, "L1ArbitrumGovernor: ZERO_LOOKBACK");
        maxProposalBlockLookback = _maxProposalBlockLookback;
    }

    /// @notice Create a proposal, checking the proposer's threshold at a chosen block instead of
    ///         block.number - 1.
    /// @dev    thresholdBlock may be up to maxProposalBlockLookback blocks old, so the proposer can
    ///         checkpoint an assertion, prove their votes against it, and propose without
    ///         predicting the block their tx lands in.
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint256 thresholdBlock
    ) public virtual returns (uint256) {
        require(
            thresholdBlock < block.number
                && block.number - thresholdBlock <= maxProposalBlockLookback,
            "L1ArbitrumGovernor: THRESHOLD_BLOCK_OUT_OF_RANGE"
        );
        _thresholdBlockOverride = thresholdBlock;
        uint256 proposalId = super.propose(targets, values, calldatas, description);
        _thresholdBlockOverride = 0;
        return proposalId;
    }

    /// @notice Voting power of an account as of a block number.
    /// @dev The base governor checks proposer power at block.number - 1 inside {propose}. While
    ///      the 5-arg propose overload runs, that lookup is redirected to the proposer's chosen
    ///      threshold block. All other callers, including vote tallying, get the value at the
    ///      block they ask for.
    function getVotes(address account, uint256 blockNumber)
        public
        view
        virtual
        override(IGovernorUpgradeable, GovernorUpgradeable)
        returns (uint256)
    {
        uint256 overrideBlock = _thresholdBlockOverride;
        return super.getVotes(account, overrideBlock != 0 ? overrideBlock : blockNumber);
    }

    /// @notice Permissionlessly lock a proposal's snapshot to a chosen block. Required before
    ///         any vote can be cast. Must be performed while the proposal is Active.
    ///         blockNumber may be any past block at or after the original snapshot.
    function lockProposalSnapshot(uint256 proposalId, uint256 blockNumber) external {
        require(
            state(proposalId) == ProposalState.Active, "L1ArbitrumGovernor: PROPOSAL_NOT_ACTIVE"
        );
        require(!proposalSnapshotLocked[proposalId], "L1ArbitrumGovernor: SNAPSHOT_LOCKED");
        require(
            blockNumber >= proposalSnapshot(proposalId) && blockNumber < block.number,
            "L1ArbitrumGovernor: SNAPSHOT_BLOCK_OUT_OF_RANGE"
        );
        // reverts unless quorum inputs are proven at blockNumber's assertion
        // this ensures that the blockNumber has a valid assertion snapshotted
        // in the L2 state mirror
        quorum(blockNumber);

        // voteStart consumers, and why a one-time increase is safe for each:
        // - propose(): voteStart.isUnset() guards duplicate proposals
        // - state(): snapshot==0 means unknown proposal, snapshot >= block.number means Pending.
        //   The new value is nonzero and < block.number, and voteEnd is stored separately, so
        //   the proposal stays Active.
        // - _castVote(): the block at which vote weight is fetched. Votes require the lock, so
        //   all weights use the same block.
        // - _quorumReached() via quorum(proposalSnapshot()): total delegation, exclude-address
        //   votes, and the quorum numerator are read at the same block as vote weights.
        // - proposalSnapshot() getter: offchain consumers see the new value; only the
        //   ProposalCreated event retains the original.
        proposalSnapshotLocked[proposalId] = true;
        _proposals[proposalId].voteStart.setDeadline(uint64(blockNumber));
        emit ProposalSnapshotLocked(proposalId, blockNumber);
    }

    /// @dev The exclude address is an L2-native address with no L1 claimant, so we skip the
    ///      L1<>L2 address resolution.
    function _getExcludeVotes(uint256 blockNumber)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return IVotingTokenMirror(address(token)).getPastVotesByL2(EXCLUDE_ADDRESS, blockNumber);
    }

    /// @dev Votes additionally require the snapshot to be locked; see {lockProposalSnapshot}.
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual override returns (uint256) {
        // checked before the lock so a Pending proposal reverts with the standard message
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");
        require(proposalSnapshotLocked[proposalId], "L1ArbitrumGovernor: SNAPSHOT_NOT_LOCKED");
        return super._castVote(proposalId, account, support, reason, params);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     */
    uint256[47] private __gap;
}
