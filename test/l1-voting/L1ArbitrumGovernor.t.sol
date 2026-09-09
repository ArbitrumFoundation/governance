// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {L1ArbitrumGovernor} from "../../src/l1-voting/L1ArbitrumGovernor.sol";
import {IVotingTokenMirror, VotingTokenMirror} from "../../src/l1-voting/VotingTokenMirror.sol";
import {L2StateMirror} from "../../src/l1-voting/L2StateMirror.sol";
import {ArbitrumTimelock} from "../../src/ArbitrumTimelock.sol";
import {TestUtil} from "../util/TestUtil.sol";
import {
    IVotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {
    IGovernorUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";

contract MockVotingTokenMirror is IVotingTokenMirror {
    mapping(address => address) public claimed; // L1 account -> claimed L2 delegate
    mapping(address => mapping(uint256 => address)) public l1AddressAt; // L2 delegate's proven claim
    mapping(address => mapping(uint256 => uint256)) public votesAt; // L2 account's proven votes
    mapping(uint256 => uint256) public totalDelegation;

    function setClaimed(address l1Account, address l2Delegate) external {
        claimed[l1Account] = l2Delegate;
    }

    function setL1AddressAt(address l2Delegate, uint256 blockNumber, address l1Account) external {
        l1AddressAt[l2Delegate][blockNumber] = l1Account;
    }

    function setVotesAt(address l2Account, uint256 blockNumber, uint256 votes) external {
        votesAt[l2Account][blockNumber] = votes;
    }

    function setTotalDelegationAt(uint256 blockNumber, uint256 amount) external {
        totalDelegation[blockNumber] = amount;
    }

    /// @notice One-call voter setup: l1Account claims l2Delegate, whose claim-back and votes are
    /// proven at a block
    function proveVotes(address l1Account, address l2Delegate, uint256 blockNumber, uint256 votes)
        external
    {
        claimed[l1Account] = l2Delegate;
        l1AddressAt[l2Delegate][blockNumber] = l1Account;
        votesAt[l2Delegate][blockNumber] = votes;
    }

    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256) {
        address l2Delegate = claimed[account];
        if (l2Delegate == address(0)) {
            revert VotingTokenMirror.NotClaimed(account);
        }
        address claimedL1 = l1AddressAt[l2Delegate][blockNumber];
        if (claimedL1 == address(0)) {
            revert L2StateMirror.L1AddressNotProven();
        }
        if (claimedL1 != account) {
            revert VotingTokenMirror.ClaimMismatch(account, l2Delegate, claimedL1);
        }
        return _votes(l2Delegate, blockNumber);
    }

    function getPastVotesByL2(address l2Account, uint256 blockNumber)
        external
        view
        returns (uint256)
    {
        return _votes(l2Account, blockNumber);
    }

    function getTotalDelegationAt(uint256 blockNumber) external view returns (uint256) {
        uint256 amount = totalDelegation[blockNumber];
        if (amount == 0) {
            revert L2StateMirror.TotalDelegationNotProven();
        }
        return amount;
    }

    function _votes(address l2Account, uint256 blockNumber) private view returns (uint256) {
        uint256 votes = votesAt[l2Account][blockNumber];
        if (votes == 0) {
            revert L2StateMirror.VotesNotProven();
        }
        return votes;
    }
}

contract Payload {
    uint256 public count;

    function increment() external {
        count++;
    }
}

contract L1ArbitrumGovernorTest is Test {
    uint256 constant VOTING_DELAY = 100;
    uint256 constant VOTING_PERIOD = 1000;
    uint256 constant QUORUM_NUMERATOR = 5000; // 50%, denominator 10_000
    uint256 constant THRESHOLD = 100e18;
    uint64 constant MIN_PERIOD_AFTER_QUORUM = 50;
    uint256 constant MIN_QUORUM = 200e18;
    uint256 constant MAX_QUORUM = 1_000_000e18;
    uint256 constant MAX_LOOKBACK = 300;
    uint256 constant TIMELOCK_DELAY = 1 days;

    uint256 constant TOTAL_DELEGATION = 2000e18;
    uint256 constant EXCLUDE_VOTES = 400e18;
    // (TOTAL_DELEGATION - EXCLUDE_VOTES) * QUORUM_NUMERATOR / 10_000
    uint256 constant QUORUM = 800e18;

    string constant DESCRIPTION = "test proposal";

    L1ArbitrumGovernor gov;
    MockVotingTokenMirror mirror;
    ArbitrumTimelock timelock;
    Payload payload;
    address exclude;
    uint256 deployBlock;

    address owner = makeAddr("owner");
    address proposer = makeAddr("proposer");
    address proposerL2 = makeAddr("proposerL2");
    address voter = makeAddr("voter");
    address voterL2 = makeAddr("voterL2");

    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );
    event VoteCast(
        address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason
    );
    event ProposalSnapshotLocked(uint256 indexed proposalId, uint256 blockNumber);

    function setUp() public {
        vm.roll(1000);
        deployBlock = block.number;

        mirror = new MockVotingTokenMirror();
        payload = new Payload();
        gov = L1ArbitrumGovernor(payable(TestUtil.deployProxy(address(new L1ArbitrumGovernor()))));
        timelock = ArbitrumTimelock(payable(TestUtil.deployProxy(address(new ArbitrumTimelock()))));

        address[] memory proposers = new address[](1);
        proposers[0] = address(gov);
        timelock.initialize(TIMELOCK_DELAY, proposers, new address[](1)); // executor 0 = anyone

        gov.initialize(
            IVotesUpgradeable(address(mirror)),
            timelock,
            owner,
            VOTING_DELAY,
            VOTING_PERIOD,
            QUORUM_NUMERATOR,
            THRESHOLD,
            MIN_PERIOD_AFTER_QUORUM,
            MIN_QUORUM,
            MAX_QUORUM,
            MAX_LOOKBACK
        );
        exclude = gov.EXCLUDE_ADDRESS();
    }

    function _freshGov() internal returns (L1ArbitrumGovernor) {
        return L1ArbitrumGovernor(payable(TestUtil.deployProxy(address(new L1ArbitrumGovernor()))));
    }

    function _propArgs()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        targets[0] = address(payload);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(Payload.increment, ());
    }

    function _propose() internal returns (uint256) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _propArgs();
        vm.prank(proposer);
        return gov.propose(targets, values, calldatas, DESCRIPTION, block.number - 1);
    }

    /// @dev proves proposer votes at the previous block, proposes with it as the threshold
    ///      block, and rolls into the voting period
    function _proposeAndRollToActive() internal returns (uint256 id, uint256 snapshot) {
        mirror.proveVotes(proposer, proposerL2, block.number - 1, THRESHOLD);
        id = _propose();
        snapshot = gov.proposalSnapshot(id);
        vm.roll(snapshot + 1);
    }

    function _proveQuorumInputs(uint256 blockNumber) internal {
        mirror.setTotalDelegationAt(blockNumber, TOTAL_DELEGATION);
        mirror.setVotesAt(exclude, blockNumber, EXCLUDE_VOTES);
    }

    /// @dev proves quorum inputs at the snapshot and locks it; required before any vote
    function _proveAndLockSnapshot(uint256 id, uint256 snapshot) internal {
        _proveQuorumInputs(snapshot);
        gov.lockProposalSnapshot(id, snapshot);
    }

    function _assertState(uint256 id, IGovernorUpgradeable.ProposalState expected) internal {
        assertEq(uint256(gov.state(id)), uint256(expected));
    }

    // --- initialization ---

    function testL2InitializerReverts() public {
        L1ArbitrumGovernor fresh = _freshGov();
        vm.expectRevert("L1ArbitrumGovernor: WRONG_INITIALIZER");
        fresh.initialize(IVotesUpgradeable(address(mirror)), timelock, owner, 1, 2, 3, 4, 5);
    }

    function testInitialize() public {
        assertEq(gov.name(), "L1ArbitrumGovernor");
        assertEq(gov.owner(), owner);
        assertEq(address(gov.token()), address(mirror));
        assertEq(gov.timelock(), address(timelock));
        assertEq(gov.votingDelay(), VOTING_DELAY);
        assertEq(gov.votingPeriod(), VOTING_PERIOD);
        assertEq(gov.quorumNumerator(), QUORUM_NUMERATOR);
        assertEq(gov.proposalThreshold(), THRESHOLD);
        assertEq(gov.lateQuorumVoteExtension(), MIN_PERIOD_AFTER_QUORUM);
        assertEq(gov.dvpQuorumStartBlock(), deployBlock);
        assertEq(gov.maxProposalBlockLookback(), MAX_LOOKBACK);

        vm.roll(block.number + 1);
        assertEq(gov.minimumQuorum(deployBlock), MIN_QUORUM);
        assertEq(gov.maximumQuorum(deployBlock), MAX_QUORUM);

        vm.expectRevert("Initializable: contract is already initialized");
        gov.initialize(
            IVotesUpgradeable(address(mirror)),
            timelock,
            owner,
            VOTING_DELAY,
            VOTING_PERIOD,
            QUORUM_NUMERATOR,
            THRESHOLD,
            MIN_PERIOD_AFTER_QUORUM,
            MIN_QUORUM,
            MAX_QUORUM,
            MAX_LOOKBACK
        );
    }

    function testInitializeMinGteMaxQuorumReverts() public {
        L1ArbitrumGovernor fresh = _freshGov();
        vm.expectRevert("L2ArbitrumGovernor: MIN_GT_MAX");
        fresh.initialize(
            IVotesUpgradeable(address(mirror)), timelock, owner, 1, 2, 3, 4, 5, 200, 200, 1
        );

        vm.expectRevert("L2ArbitrumGovernor: MIN_GT_MAX");
        fresh.initialize(
            IVotesUpgradeable(address(mirror)), timelock, owner, 1, 2, 3, 4, 5, 300, 200, 1
        );
    }

    function testInitializeZeroLookbackReverts() public {
        L1ArbitrumGovernor fresh = _freshGov();
        vm.expectRevert("L1ArbitrumGovernor: ZERO_LOOKBACK");
        fresh.initialize(
            IVotesUpgradeable(address(mirror)), timelock, owner, 1, 2, 3, 4, 5, 200, 300, 0
        );
    }

    function testPostUpgradeInitReverts() public {
        // quorum history is set during init, so the L2 migration path is dead on L1
        vm.prank(owner);
        vm.expectRevert("L2ArbitrumGovernor: ALREADY_INITIALIZED");
        gov.postUpgradeInit(1, 2, 3);
    }

    // --- setMaxProposalBlockLookback ---

    function testSetMaxProposalBlockLookbackViaRelay() public {
        vm.prank(owner);
        gov.relay(
            address(gov),
            0,
            abi.encodeCall(L1ArbitrumGovernor.setMaxProposalBlockLookback, (MAX_LOOKBACK + 1))
        );
        assertEq(gov.maxProposalBlockLookback(), MAX_LOOKBACK + 1);
    }

    function testSetMaxProposalBlockLookbackDirectCallReverts() public {
        vm.prank(owner);
        vm.expectRevert("Governor: onlyGovernance");
        gov.setMaxProposalBlockLookback(1);

        vm.prank(makeAddr("rando"));
        vm.expectRevert("Governor: onlyGovernance");
        gov.setMaxProposalBlockLookback(1);
    }

    function testSetMaxProposalBlockLookbackZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert("L1ArbitrumGovernor: ZERO_LOOKBACK");
        gov.relay(
            address(gov), 0, abi.encodeCall(L1ArbitrumGovernor.setMaxProposalBlockLookback, (0))
        );
    }

    // --- propose ---

    function testProposeSucceeds() public {
        mirror.proveVotes(proposer, proposerL2, block.number - 1, THRESHOLD);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _propArgs();
        uint256 id = gov.hashProposal(targets, values, calldatas, keccak256(bytes(DESCRIPTION)));
        uint256 snapshot = block.number + VOTING_DELAY;

        vm.expectEmit();
        emit ProposalCreated(
            id,
            proposer,
            targets,
            values,
            new string[](1),
            calldatas,
            snapshot,
            snapshot + VOTING_PERIOD,
            DESCRIPTION
        );
        assertEq(_propose(), id);

        assertEq(gov.proposalSnapshot(id), snapshot);
        _assertState(id, IGovernorUpgradeable.ProposalState.Pending);
    }

    function testProposeMeasuresThresholdAtChosenBlock() public {
        // below threshold at block.number - 1 (where the base governor checks), at threshold at
        // the chosen older block; success pins the threshold block redirect
        uint256 thresholdBlock = block.number - 10;
        mirror.proveVotes(proposer, proposerL2, block.number - 1, 1);
        mirror.proveVotes(proposer, proposerL2, thresholdBlock, THRESHOLD);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _propArgs();
        vm.prank(proposer);
        gov.propose(targets, values, calldatas, DESCRIPTION, thresholdBlock);
    }

    function testProposeThresholdBlockAtLookbackLimit() public {
        uint256 thresholdBlock = block.number - MAX_LOOKBACK;
        mirror.proveVotes(proposer, proposerL2, thresholdBlock, THRESHOLD);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _propArgs();
        vm.prank(proposer);
        gov.propose(targets, values, calldatas, DESCRIPTION, thresholdBlock);
    }

    function testProposeThresholdBlockOutOfRangeReverts() public {
        mirror.proveVotes(proposer, proposerL2, block.number - 1, THRESHOLD);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _propArgs();

        // older than the lookback allows
        vm.prank(proposer);
        vm.expectRevert("L1ArbitrumGovernor: THRESHOLD_BLOCK_OUT_OF_RANGE");
        gov.propose(targets, values, calldatas, DESCRIPTION, block.number - MAX_LOOKBACK - 1);

        // current block
        vm.prank(proposer);
        vm.expectRevert("L1ArbitrumGovernor: THRESHOLD_BLOCK_OUT_OF_RANGE");
        gov.propose(targets, values, calldatas, DESCRIPTION, block.number);

        // future block; reverts cleanly instead of underflowing
        vm.prank(proposer);
        vm.expectRevert("L1ArbitrumGovernor: THRESHOLD_BLOCK_OUT_OF_RANGE");
        gov.propose(targets, values, calldatas, DESCRIPTION, block.number + 1);
    }

    function testFourArgProposeStillCallable() public {
        // the inherited 4-arg propose stays exposed, measuring the threshold at
        // block.number - 1 with no redirect; the mock reverts at any other block
        mirror.proveVotes(proposer, proposerL2, block.number - 1, THRESHOLD);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _propArgs();
        vm.prank(proposer);
        uint256 id = gov.propose(targets, values, calldatas, DESCRIPTION);
        assertEq(gov.proposalSnapshot(id), block.number + VOTING_DELAY);
    }

    function testProposeBelowThresholdReverts() public {
        mirror.proveVotes(proposer, proposerL2, block.number - 1, THRESHOLD - 1);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _propArgs();
        vm.prank(proposer);
        vm.expectRevert("Governor: proposer votes below proposal threshold");
        gov.propose(targets, values, calldatas, DESCRIPTION, block.number - 1);
    }

    function testProposeUnclaimedProposerReverts() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _propArgs();
        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(VotingTokenMirror.NotClaimed.selector, proposer));
        gov.propose(targets, values, calldatas, DESCRIPTION, block.number - 1);
    }

    function testProposeUnprovenVotesReverts() public {
        // claimed both ways at the threshold block, but votes not proven
        mirror.setClaimed(proposer, proposerL2);
        mirror.setL1AddressAt(proposerL2, block.number - 1, proposer);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _propArgs();
        vm.prank(proposer);
        vm.expectRevert(L2StateMirror.VotesNotProven.selector);
        gov.propose(targets, values, calldatas, DESCRIPTION, block.number - 1);
    }

    // --- getVotes ---

    function testGetVotesHonorsRequestedBlock() public {
        // votes proven for the L2 delegate; the governor is queried with the L1 account
        mirror.proveVotes(voter, voterL2, 900, 1e18);
        mirror.proveVotes(voter, voterL2, 950, 2e18);
        assertEq(gov.getVotes(voter, 900), 1e18);
        assertEq(gov.getVotes(voter, 950), 2e18);
    }

    function testGetVotesUnprovenReverts() public {
        mirror.setClaimed(voter, voterL2);
        mirror.setL1AddressAt(voterL2, 900, voter);
        vm.expectRevert(L2StateMirror.VotesNotProven.selector);
        gov.getVotes(voter, 900);
    }

    // --- voting ---

    function testCastVoteForAgainstAbstain() public {
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        _proveAndLockSnapshot(id, snapshot);

        address voterFor = makeAddr("voterFor");
        address voterAgainst = makeAddr("voterAgainst");
        address voterAbstain = makeAddr("voterAbstain");
        mirror.proveVotes(voterFor, makeAddr("voterForL2"), snapshot, 500e18);
        mirror.proveVotes(voterAgainst, makeAddr("voterAgainstL2"), snapshot, 100e18);
        mirror.proveVotes(voterAbstain, makeAddr("voterAbstainL2"), snapshot, 50e18);

        vm.expectEmit();
        emit VoteCast(voterFor, id, 1, 500e18, "");
        vm.prank(voterFor);
        gov.castVote(id, 1);

        vm.expectEmit();
        emit VoteCast(voterAgainst, id, 0, 100e18, "");
        vm.prank(voterAgainst);
        gov.castVote(id, 0);

        vm.expectEmit();
        emit VoteCast(voterAbstain, id, 2, 50e18, "");
        vm.prank(voterAbstain);
        gov.castVote(id, 2);

        (uint256 against, uint256 forVotes, uint256 abstain) = gov.proposalVotes(id);
        assertEq(against, 100e18);
        assertEq(forVotes, 500e18);
        assertEq(abstain, 50e18);
        assertTrue(gov.hasVoted(id, voterFor));
        assertTrue(gov.hasVoted(id, voterAgainst));
        assertTrue(gov.hasVoted(id, voterAbstain));
    }

    function testCastVoteWeighsAtSnapshot() public {
        // models power shifting during the long voting delay, with a fresher assertion
        // checkpointed before the snapshot
        mirror.proveVotes(proposer, proposerL2, block.number - 1, THRESHOLD);
        mirror.proveVotes(voter, voterL2, block.number, 111e18); // propose block
        uint256 id = _propose();
        uint256 snapshot = gov.proposalSnapshot(id);
        mirror.proveVotes(voter, voterL2, snapshot, 222e18); // snapshot
        vm.roll(snapshot + 1);
        mirror.proveVotes(voter, voterL2, block.number, 333e18); // vote block
        _proveAndLockSnapshot(id, snapshot);

        vm.expectEmit();
        emit VoteCast(voter, id, 1, 222e18, "");
        vm.prank(voter);
        gov.castVote(id, 1);
    }

    function testCastVotePendingReverts() public {
        // pins the check ordering in _castVote: a Pending proposal gets the standard OZ
        // error, not SNAPSHOT_NOT_LOCKED
        mirror.proveVotes(proposer, proposerL2, block.number - 1, THRESHOLD);
        uint256 id = _propose();
        vm.prank(voter);
        vm.expectRevert("Governor: vote not currently active");
        gov.castVote(id, 1);
    }

    function testCastVoteSnapshotNotLockedReverts() public {
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        _proveQuorumInputs(snapshot);
        mirror.proveVotes(voter, voterL2, snapshot, 500e18);
        vm.prank(voter);
        vm.expectRevert("L1ArbitrumGovernor: SNAPSHOT_NOT_LOCKED");
        gov.castVote(id, 1);
    }

    function testCastVoteUnclaimedVoterReverts() public {
        // delta from stock OZ: zero-power accounts cannot cast 0-weight votes
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        _proveAndLockSnapshot(id, snapshot);
        vm.prank(voter);
        vm.expectRevert(abi.encodeWithSelector(VotingTokenMirror.NotClaimed.selector, voter));
        gov.castVote(id, 1);
    }

    function testCastVoteClaimMismatchReverts() public {
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        _proveAndLockSnapshot(id, snapshot);
        address delegateL2 = makeAddr("delegateL2");
        address otherL1 = makeAddr("otherL1");
        mirror.setClaimed(voter, delegateL2);
        mirror.setL1AddressAt(delegateL2, snapshot, otherL1);
        vm.prank(voter);
        vm.expectRevert(
            abi.encodeWithSelector(
                VotingTokenMirror.ClaimMismatch.selector, voter, delegateL2, otherL1
            )
        );
        gov.castVote(id, 1);
    }

    function testCastVoteUnprovenVotesReverts() public {
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        _proveAndLockSnapshot(id, snapshot);
        mirror.setClaimed(voter, voterL2);
        mirror.setL1AddressAt(voterL2, snapshot, voter);
        vm.prank(voter);
        vm.expectRevert(L2StateMirror.VotesNotProven.selector);
        gov.castVote(id, 1);
    }

    // --- lockProposalSnapshot ---

    function testLockSnapshotSetsStateAndEmits() public {
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        uint256 deadline = gov.proposalDeadline(id);
        _proveQuorumInputs(snapshot);

        assertFalse(gov.proposalSnapshotLocked(id));
        vm.expectEmit();
        emit ProposalSnapshotLocked(id, snapshot);
        gov.lockProposalSnapshot(id, snapshot);

        assertTrue(gov.proposalSnapshotLocked(id));
        assertEq(gov.proposalSnapshot(id), snapshot);
        assertEq(gov.proposalDeadline(id), deadline);
        _assertState(id, IGovernorUpgradeable.ProposalState.Active);
    }

    function testLockSnapshotToLaterBlockMovesWeights() public {
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        vm.roll(snapshot + 10);
        uint256 lockBlock = block.number - 1; // also the latest lockable block

        // different proven values at the original snapshot and the locked block
        _proveQuorumInputs(snapshot);
        mirror.setTotalDelegationAt(lockBlock, 2 * TOTAL_DELEGATION);
        mirror.setVotesAt(exclude, lockBlock, 2 * EXCLUDE_VOTES);
        mirror.proveVotes(voter, voterL2, snapshot, 111e18);
        mirror.proveVotes(voter, voterL2, lockBlock, 222e18);

        gov.lockProposalSnapshot(id, lockBlock);
        assertEq(gov.proposalSnapshot(id), lockBlock);

        // vote weight and quorum both come from the locked block
        vm.expectEmit();
        emit VoteCast(voter, id, 1, 222e18, "");
        vm.prank(voter);
        gov.castVote(id, 1);
        assertEq(gov.quorum(gov.proposalSnapshot(id)), 2 * QUORUM);
    }

    function testLockSnapshotWhenOriginalSnapshotUnprovable() public {
        // quorum inputs only provable at a later block, i.e. the original snapshot block has
        // no checkpoint; the case lockProposalSnapshot exists to solve
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        vm.roll(snapshot + 10);
        uint256 lockBlock = snapshot + 5;

        vm.expectRevert(L2StateMirror.TotalDelegationNotProven.selector);
        gov.lockProposalSnapshot(id, snapshot);

        _proveQuorumInputs(lockBlock);
        gov.lockProposalSnapshot(id, lockBlock);

        mirror.proveVotes(voter, voterL2, lockBlock, QUORUM);
        vm.prank(voter);
        gov.castVote(id, 1);

        vm.roll(gov.proposalDeadline(id) + 1);
        _assertState(id, IGovernorUpgradeable.ProposalState.Succeeded);
    }

    function testLockSnapshotPendingReverts() public {
        mirror.proveVotes(proposer, proposerL2, block.number - 1, THRESHOLD);
        uint256 id = _propose();
        uint256 snapshot = gov.proposalSnapshot(id);
        vm.expectRevert("L1ArbitrumGovernor: PROPOSAL_NOT_ACTIVE");
        gov.lockProposalSnapshot(id, snapshot);
    }

    function testLockSnapshotAfterDeadlineReverts() public {
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        _proveQuorumInputs(snapshot);
        vm.roll(gov.proposalDeadline(id) + 1);
        vm.expectRevert("L1ArbitrumGovernor: PROPOSAL_NOT_ACTIVE");
        gov.lockProposalSnapshot(id, snapshot);
    }

    function testLockSnapshotUnknownProposalReverts() public {
        vm.expectRevert("Governor: unknown proposal id");
        gov.lockProposalSnapshot(12_345, 1);
    }

    function testLockSnapshotTwiceReverts() public {
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        _proveAndLockSnapshot(id, snapshot);
        vm.expectRevert("L1ArbitrumGovernor: SNAPSHOT_LOCKED");
        gov.lockProposalSnapshot(id, snapshot);
    }

    function testLockSnapshotBlockOutOfRangeReverts() public {
        // valid range is [snapshot, block.number); block.number is snapshot + 1 here
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        _proveQuorumInputs(snapshot);

        vm.expectRevert("L1ArbitrumGovernor: SNAPSHOT_BLOCK_OUT_OF_RANGE");
        gov.lockProposalSnapshot(id, snapshot - 1);

        vm.expectRevert("L1ArbitrumGovernor: SNAPSHOT_BLOCK_OUT_OF_RANGE");
        gov.lockProposalSnapshot(id, block.number);

        vm.expectRevert("L1ArbitrumGovernor: SNAPSHOT_BLOCK_OUT_OF_RANGE");
        gov.lockProposalSnapshot(id, block.number + 1);
    }

    function testLockSnapshotTotalDelegationUnprovenReverts() public {
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        vm.expectRevert(L2StateMirror.TotalDelegationNotProven.selector);
        gov.lockProposalSnapshot(id, snapshot);
    }

    function testLockSnapshotExcludeVotesUnprovenReverts() public {
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        mirror.setTotalDelegationAt(snapshot, TOTAL_DELEGATION);
        vm.expectRevert(L2StateMirror.VotesNotProven.selector);
        gov.lockProposalSnapshot(id, snapshot);
    }

    // --- quorum ---

    function testQuorumFormula() public {
        uint256 blockNumber = block.number;
        vm.roll(block.number + 1);
        _proveQuorumInputs(blockNumber);
        assertEq(
            gov.quorum(blockNumber), (TOTAL_DELEGATION - EXCLUDE_VOTES) * QUORUM_NUMERATOR / 10_000
        );
        assertEq(gov.quorum(blockNumber), QUORUM);
    }

    function testQuorumExcludeVotesUseL2NativePath() public {
        uint256 blockNumber = block.number;
        vm.roll(block.number + 1);
        _proveQuorumInputs(blockNumber);
        // the exclude address never claims on L1, so the L1 claim-resolution path reverts...
        vm.expectRevert(abi.encodeWithSelector(VotingTokenMirror.NotClaimed.selector, exclude));
        mirror.getPastVotes(exclude, blockNumber);
        // ...yet quorum computes, pinning the L2-native _getExcludeVotes override
        assertEq(gov.quorum(blockNumber), QUORUM);
    }

    // --- lifecycle and state() ---

    function testFullLifecycle() public {
        mirror.proveVotes(proposer, proposerL2, block.number - 1, THRESHOLD);
        uint256 id = _propose();
        _assertState(id, IGovernorUpgradeable.ProposalState.Pending);

        uint256 snapshot = gov.proposalSnapshot(id);
        vm.roll(snapshot + 1);
        _assertState(id, IGovernorUpgradeable.ProposalState.Active);

        _proveAndLockSnapshot(id, snapshot);
        mirror.proveVotes(voter, voterL2, snapshot, QUORUM);
        vm.prank(voter);
        gov.castVote(id, 1);

        vm.roll(gov.proposalDeadline(id) + 1);
        _assertState(id, IGovernorUpgradeable.ProposalState.Succeeded);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _propArgs();
        bytes32 descriptionHash = keccak256(bytes(DESCRIPTION));
        gov.queue(targets, values, calldatas, descriptionHash);
        _assertState(id, IGovernorUpgradeable.ProposalState.Queued);

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        gov.execute(targets, values, calldatas, descriptionHash);
        _assertState(id, IGovernorUpgradeable.ProposalState.Executed);
        assertEq(payload.count(), 1);
    }

    function testStateRevertsUntilQuorumInputsProven() public {
        mirror.proveVotes(proposer, proposerL2, block.number - 1, THRESHOLD);
        uint256 id = _propose();
        uint256 snapshot = gov.proposalSnapshot(id);
        vm.roll(gov.proposalDeadline(id) + 1);

        vm.expectRevert(L2StateMirror.TotalDelegationNotProven.selector);
        gov.state(id);

        mirror.setTotalDelegationAt(snapshot, TOTAL_DELEGATION);
        vm.expectRevert(L2StateMirror.VotesNotProven.selector);
        gov.state(id);

        mirror.setVotesAt(exclude, snapshot, EXCLUDE_VOTES);
        _assertState(id, IGovernorUpgradeable.ProposalState.Defeated);
    }

    function testUnlockedProposalCannotQueue() public {
        // a proposal whose snapshot is never locked receives no votes and dies at the deadline
        (uint256 id, uint256 snapshot) = _proposeAndRollToActive();
        _proveQuorumInputs(snapshot);
        vm.roll(gov.proposalDeadline(id) + 1);
        _assertState(id, IGovernorUpgradeable.ProposalState.Defeated);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _propArgs();
        vm.expectRevert("Governor: proposal not successful");
        gov.queue(targets, values, calldatas, keccak256(bytes(DESCRIPTION)));
    }

    // --- known quirks ---

    function testGetPastCirculatingSupplyReverts() public {
        // the mirror lacks getPastTotalSupply; only reachable via the pre-DVP quorum branch,
        // which is dead on L1 (dvpQuorumStartBlock == init block)
        vm.expectRevert();
        gov.getPastCirculatingSupply(block.number - 1);
    }
}
