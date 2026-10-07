// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {L1ArbitrumGovernor} from "../../src/l1-voting/L1ArbitrumGovernor.sol";
import {L2StateMirror} from "../../src/l1-voting/L2StateMirror.sol";
import {VotingTokenMirror} from "../../src/l1-voting/VotingTokenMirror.sol";
import {DelegateMapping} from "../../src/l1-voting/DelegateMapping.sol";
import {ProofHelper} from "../../src/l1-voting/ProofHelper.sol";
import {ArbitrumTimelock} from "../../src/ArbitrumTimelock.sol";
import {MockRollup} from "./L2StateMirror.t.sol";
import {Payload} from "./L1ArbitrumGovernor.t.sol";
import {TestUtil} from "../util/TestUtil.sol";
import {AssertionState} from "@arbitrum/nitro-contracts/src/rollup/IRollupCore.sol";
import {MachineStatus} from "@arbitrum/nitro-contracts/src/state/Machine.sol";
import {
    IVotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {
    IGovernorUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";

/// @notice Full-stack proposal lifecycle over the mainnet fixture
contract L1ArbitrumGovernorIntegrationTest is Test {
    uint256 constant VOTING_DELAY = 100;
    uint256 constant VOTING_PERIOD = 1000;
    uint256 constant QUORUM_NUMERATOR = 100; // 1%, denominator 10_000
    uint256 constant PROPOSAL_THRESHOLD = 1_000_000 ether;
    uint64 constant MIN_PERIOD_AFTER_QUORUM = 50;
    uint256 constant MIN_QUORUM = 1_000_000 ether;
    uint256 constant MAX_QUORUM = 500_000_000 ether;
    uint256 constant MAX_LOOKBACK = 300;
    uint256 constant TIMELOCK_DELAY = 1 days;

    string constant DESCRIPTION = "integration proposal";

    L1ArbitrumGovernor gov;
    VotingTokenMirror tokenMirror;
    L2StateMirror stateMirror;
    DelegateMapping delegateMapping;
    ArbitrumTimelock timelock;
    Payload payload;
    string json;
    bytes32 assertionHash;
    address delegateL2;
    address delegateL1;
    uint256 delegateVotes;

    function setUp() public {
        json = vm.readFile(
            string.concat(vm.projectRoot(), "/test/l1-voting/fixtures/l2_state_mirror.json")
        );
        assertionHash = vm.parseJsonBytes32(json, ".assertionHash");
        delegateL2 = vm.parseJsonAddress(json, ".delegateAccount");
        delegateL1 = vm.parseJsonAddress(json, ".expectedDelegateL1Address");
        delegateVotes = vm.parseJsonUint(json, ".expectedDelegateVotes");

        MockRollup rollup = new MockRollup(assertionHash);
        stateMirror = new L2StateMirror(
            address(new ProofHelper()),
            vm.parseJsonAddress(json, ".l2TokenAddress"),
            vm.parseJsonUint(json, ".delegateCheckpointsSlot"),
            vm.parseJsonUint(json, ".totalDelegationSlot"),
            vm.parseJsonAddress(json, ".l2DelegateMappingAddress"),
            vm.parseJsonUint(json, ".l2DelegateMappingL1AddressSlot"),
            address(rollup)
        );
        delegateMapping = new DelegateMapping();
        tokenMirror = new VotingTokenMirror(address(stateMirror), address(delegateMapping));
        payload = new Payload();

        // checkpoint the assertion and prove the full snapshot: header, both storage roots,
        // total delegation, exclude votes, and the delegate's votes + claimed L1 address
        stateMirror.checkpointAssertion();
        AssertionState memory afterState;
        afterState.globalState.bytes32Vals[0] = vm.parseJsonBytes32(json, ".l2BlockHash");
        afterState.globalState.bytes32Vals[1] = vm.parseJsonBytes32(json, ".sendRoot");
        afterState.globalState.u64Vals[0] = uint64(vm.parseJsonUint(json, ".inboxPosition"));
        afterState.globalState.u64Vals[1] = uint64(vm.parseJsonUint(json, ".positionInMessage"));
        afterState.machineStatus = MachineStatus(vm.parseJsonUint(json, ".machineStatus"));
        afterState.endHistoryRoot = vm.parseJsonBytes32(json, ".endHistoryRoot");
        stateMirror.proveL2BlockHeader(
            assertionHash,
            vm.parseJsonBytes32(json, ".parentAssertionHash"),
            afterState,
            vm.parseJsonBytes32(json, ".inboxAcc"),
            vm.parseJsonBytes(json, ".blockHeaderRlp")
        );
        stateMirror.proveTokenStorageRoot(
            assertionHash, vm.parseJsonBytesArray(json, ".accountProof")
        );
        stateMirror.proveDelegateMappingStorageRoot(
            assertionHash, vm.parseJsonBytesArray(json, ".delegateMappingAccountProof")
        );
        stateMirror.proveTotalDelegation(
            assertionHash,
            vm.parseJsonBytesArray(json, ".totalDelegationLenProof"),
            vm.parseJsonBytesArray(json, ".totalDelegationLastCheckpointProof")
        );
        stateMirror.proveVotes(
            assertionHash,
            vm.parseJsonAddress(json, ".excludeAddress"),
            vm.parseJsonBytesArray(json, ".checkpointLenProof"),
            vm.parseJsonBytesArray(json, ".lastCheckpointProof")
        );
        stateMirror.proveVotes(
            assertionHash,
            delegateL2,
            vm.parseJsonBytesArray(json, ".delegateCheckpointLenProof"),
            vm.parseJsonBytesArray(json, ".delegateLastCheckpointProof")
        );
        stateMirror.proveL1Address(
            assertionHash, delegateL2, vm.parseJsonBytesArray(json, ".delegateL1AddressProof")
        );

        // L1-side claim: the fixture delegate's claimed L1 address claims it back
        vm.prank(delegateL1);
        delegateMapping.claim(delegateL2);

        gov = L1ArbitrumGovernor(payable(TestUtil.deployProxy(address(new L1ArbitrumGovernor()))));
        timelock = ArbitrumTimelock(payable(TestUtil.deployProxy(address(new ArbitrumTimelock()))));
        address[] memory proposers = new address[](1);
        proposers[0] = address(gov);
        timelock.initialize(TIMELOCK_DELAY, proposers, new address[](1)); // executor 0 = anyone
        gov.initialize(
            IVotesUpgradeable(address(tokenMirror)),
            timelock,
            makeAddr("owner"),
            VOTING_DELAY,
            VOTING_PERIOD,
            QUORUM_NUMERATOR,
            PROPOSAL_THRESHOLD,
            MIN_PERIOD_AFTER_QUORUM,
            MIN_QUORUM,
            MAX_QUORUM,
            MAX_LOOKBACK
        );
    }

    function testFullStackLifecycle() public {
        address[] memory targets = new address[](1);
        targets[0] = address(payload);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(Payload.increment, ());

        // setUp checkpointed the assertion and proved the delegate's votes at this block
        uint256 checkpointBlock = block.number;
        vm.roll(block.number + 1);
        vm.prank(delegateL1);
        uint256 id = gov.propose(targets, values, calldatas, DESCRIPTION, checkpointBlock);
        assertEq(uint256(gov.state(id)), uint256(IGovernorUpgradeable.ProposalState.Pending));

        uint256 snapshot = gov.proposalSnapshot(id);
        vm.roll(snapshot + 1);
        assertEq(uint256(gov.state(id)), uint256(IGovernorUpgradeable.ProposalState.Active));

        // checkpoint the (unchanged) assertion within the voting period and lock the
        // proposal's snapshot to it; the proven state carries over to the new checkpoint
        stateMirror.checkpointAssertion();
        vm.roll(block.number + 1);
        gov.lockProposalSnapshot(id, snapshot + 1);
        assertEq(gov.proposalSnapshot(id), snapshot + 1);

        // quorum reachable by the delegate alone under the scaled params
        assertLe(gov.quorum(gov.proposalSnapshot(id)), delegateVotes);
        vm.prank(delegateL1);
        gov.castVote(id, 1);
        (, uint256 forVotes,) = gov.proposalVotes(id);
        assertEq(forVotes, delegateVotes);

        vm.roll(gov.proposalDeadline(id) + 1);
        assertEq(uint256(gov.state(id)), uint256(IGovernorUpgradeable.ProposalState.Succeeded));

        bytes32 descriptionHash = keccak256(bytes(DESCRIPTION));
        gov.queue(targets, values, calldatas, descriptionHash);
        assertEq(uint256(gov.state(id)), uint256(IGovernorUpgradeable.ProposalState.Queued));

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        gov.execute(targets, values, calldatas, descriptionHash);
        assertEq(uint256(gov.state(id)), uint256(IGovernorUpgradeable.ProposalState.Executed));
        assertEq(payload.count(), 1);
    }
}
