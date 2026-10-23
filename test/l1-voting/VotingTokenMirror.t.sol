// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {L2StateMirror} from "../../src/l1-voting/L2StateMirror.sol";
import {VotingTokenMirror} from "../../src/l1-voting/VotingTokenMirror.sol";
import {DelegateMapping} from "../../src/l1-voting/DelegateMapping.sol";
import {ProofHelper} from "../../src/l1-voting/ProofHelper.sol";
import {MockRollup} from "./L2StateMirror.t.sol";
import {AssertionState} from "@arbitrum/nitro-contracts/src/rollup/IRollupCore.sol";
import {MachineStatus} from "@arbitrum/nitro-contracts/src/state/Machine.sol";

contract VotingTokenMirrorTest is Test {
    ProofHelper helper;
    L2StateMirror stateMirror;
    DelegateMapping delegateMapping;
    VotingTokenMirror tokenMirror;
    MockRollup rollup;
    string json;
    bytes32 assertionHash;
    address excludeL2;
    address delegateL2;
    address delegateL1;
    uint256 delegateVotes;

    function setUp() public {
        json = vm.readFile(
            string.concat(vm.projectRoot(), "/test/l1-voting/fixtures/l2_state_mirror.json")
        );
        helper = new ProofHelper();
        assertionHash = vm.parseJsonBytes32(json, ".assertionHash");
        rollup = new MockRollup(assertionHash);
        excludeL2 = vm.parseJsonAddress(json, ".excludeAddress");
        delegateL2 = vm.parseJsonAddress(json, ".delegateAccount");
        delegateL1 = vm.parseJsonAddress(json, ".expectedDelegateL1Address");
        delegateVotes = vm.parseJsonUint(json, ".expectedDelegateVotes");

        stateMirror = new L2StateMirror(
            address(helper),
            vm.parseJsonAddress(json, ".l2TokenAddress"),
            vm.parseJsonUint(json, ".delegateCheckpointsSlot"),
            vm.parseJsonUint(json, ".totalDelegationSlot"),
            vm.parseJsonAddress(json, ".l2DelegateMappingAddress"),
            vm.parseJsonUint(json, ".l2DelegateMappingL1AddressSlot"),
            address(rollup)
        );
        delegateMapping = new DelegateMapping();
        tokenMirror = new VotingTokenMirror(address(stateMirror), address(delegateMapping));

        // prove the full snapshot: header, both storage roots, total delegation, the exclude
        // address's votes, and the fixture delegate's votes + claimed L1 address
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
            excludeL2,
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
    }

    // --- getPastVotes ---

    function testGetPastVotesResolvesClaimedDelegate() public {
        vm.prank(delegateL1);
        delegateMapping.claim(delegateL2);
        assertEq(tokenMirror.getPastVotes(delegateL1, block.number), delegateVotes);
    }

    function testGetPastVotesUnclaimedReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(VotingTokenMirror.NotClaimed.selector, address(0xDEAD))
        );
        tokenMirror.getPastVotes(address(0xDEAD), block.number);
    }

    function testGetPastVotesOtherClaimantReverts() public {
        address attacker = address(0xBAD);
        vm.prank(attacker);
        delegateMapping.claim(delegateL2);
        vm.expectRevert(
            abi.encodeWithSelector(
                VotingTokenMirror.ClaimMismatch.selector, attacker, delegateL2, delegateL1
            )
        );
        tokenMirror.getPastVotes(attacker, block.number);
    }

    function testGetPastVotesRevokedReverts() public {
        // revoking the live L1-side claim fails closed even though the proven L2-side claim
        // still names this account
        vm.startPrank(delegateL1);
        delegateMapping.claim(delegateL2);
        delegateMapping.claim(address(0));
        vm.stopPrank();
        vm.expectRevert(
            abi.encodeWithSelector(VotingTokenMirror.NotClaimed.selector, delegateL1)
        );
        tokenMirror.getPastVotes(delegateL1, block.number);
    }

    function testGetPastVotesReclaimedUnprovenReverts() public {
        // re-pointing the live L1-side claim at a delegate with no proven claim fails closed
        vm.startPrank(delegateL1);
        delegateMapping.claim(delegateL2);
        delegateMapping.claim(address(0xCAFE));
        vm.stopPrank();
        vm.expectRevert(L2StateMirror.L1AddressNotProven.selector);
        tokenMirror.getPastVotes(delegateL1, block.number);
    }

    // --- passthroughs ---

    function testGetPastVotesByL2() public {
        assertEq(
            tokenMirror.getPastVotesByL2(excludeL2, block.number),
            vm.parseJsonUint(json, ".expectedVotes")
        );
    }

    function testGetTotalDelegationAt() public {
        assertEq(
            tokenMirror.getTotalDelegationAt(block.number),
            vm.parseJsonUint(json, ".expectedTotalDelegation")
        );
    }
}
