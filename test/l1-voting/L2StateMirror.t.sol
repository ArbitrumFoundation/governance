// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {L2StateMirror} from "../../src/l1-voting/L2StateMirror.sol";
import {ProofHelper} from "../../src/l1-voting/ProofHelper.sol";
import {IRollupCore, AssertionState} from "@arbitrum/nitro-contracts/src/rollup/IRollupCore.sol";
import {AssertionNode, AssertionStatus} from "@arbitrum/nitro-contracts/src/rollup/Assertion.sol";
import {RollupLib} from "@arbitrum/nitro-contracts/src/rollup/RollupLib.sol";
import {MachineStatus} from "@arbitrum/nitro-contracts/src/state/Machine.sol";

contract MockRollup {
    bytes32 public latestConfirmed;
    mapping(bytes32 => AssertionStatus) public statusOf;

    constructor(bytes32 _latestConfirmed) {
        setLatestConfirmed(_latestConfirmed);
    }

    function setLatestConfirmed(bytes32 _latestConfirmed) public {
        latestConfirmed = _latestConfirmed;
        statusOf[_latestConfirmed] = AssertionStatus.Confirmed;
    }

    function setStatus(bytes32 assertionHash, AssertionStatus status) external {
        statusOf[assertionHash] = status;
    }

    function getAssertion(bytes32 assertionHash) external view returns (AssertionNode memory node) {
        node.status = statusOf[assertionHash];
    }
}

contract RevertingRollup {
    fallback() external {
        revert();
    }
}

contract ShortReturnRollup {
    fallback() external {
        assembly {
            return(0, 8)
        }
    }
}

contract L2StateMirrorTest is Test {
    ProofHelper helper;
    L2StateMirror mirror;
    MockRollup rollup;
    string json;
    bytes32 assertionHash;
    address excludeL2;
    address delegateL2;

    event AssertionCheckpointed(bytes32 indexed assertionHash);
    event BlockHeaderProven(
        bytes32 indexed assertionHash, bytes32 l2StateRoot, uint256 l2BlockNumber
    );
    event TokenStorageRootProven(bytes32 indexed assertionHash, bytes32 l2TokenStorageRoot);
    event DelegateMappingStorageRootProven(
        bytes32 indexed assertionHash, bytes32 l2DelegateMappingStorageRoot
    );
    event TotalDelegationProven(bytes32 indexed assertionHash, uint256 totalDelegation);
    event VotesProven(bytes32 indexed assertionHash, address indexed account, uint256 votes);
    event L1AddressProven(
        bytes32 indexed assertionHash, address indexed l2Delegate, address indexed l1Address
    );
    event L1AddressClaimedBySig(
        bytes32 indexed assertionHash, address indexed l2Delegate, address indexed l1Address
    );

    uint256 constant eoaDelegateKey = 0xA11CE;
    address eoaDelegate;
    address constant eoaL1Address = address(0xBEEF);

    function setUp() public {
        json = vm.readFile(
            string.concat(vm.projectRoot(), "/test/l1-voting/fixtures/l2_state_mirror.json")
        );
        helper = new ProofHelper();
        assertionHash = vm.parseJsonBytes32(json, ".assertionHash");
        rollup = new MockRollup(assertionHash);
        excludeL2 = vm.parseJsonAddress(json, ".excludeAddress");
        delegateL2 = vm.parseJsonAddress(json, ".delegateAccount");
        eoaDelegate = vm.addr(eoaDelegateKey);

        mirror = _deployMirror();
        mirror.checkpointAssertion();
    }

    function _deployMirror() internal returns (L2StateMirror) {
        return _deployMirrorWithRollup(address(rollup));
    }

    function _deployMirrorWithRollup(address _rollup) internal returns (L2StateMirror) {
        return new L2StateMirror(
            address(helper),
            vm.parseJsonAddress(json, ".l2TokenAddress"),
            vm.parseJsonUint(json, ".delegateCheckpointsSlot"),
            vm.parseJsonUint(json, ".totalDelegationSlot"),
            vm.parseJsonAddress(json, ".l2DelegateMappingAddress"),
            vm.parseJsonUint(json, ".l2DelegateMappingL1AddressSlot"),
            _rollup
        );
    }

    function _afterState() internal returns (AssertionState memory s) {
        s.globalState.bytes32Vals[0] = vm.parseJsonBytes32(json, ".l2BlockHash");
        s.globalState.bytes32Vals[1] = vm.parseJsonBytes32(json, ".sendRoot");
        s.globalState.u64Vals[0] = uint64(vm.parseJsonUint(json, ".inboxPosition"));
        s.globalState.u64Vals[1] = uint64(vm.parseJsonUint(json, ".positionInMessage"));
        s.machineStatus = MachineStatus(vm.parseJsonUint(json, ".machineStatus"));
        s.endHistoryRoot = vm.parseJsonBytes32(json, ".endHistoryRoot");
    }

    function _proveHeader() internal {
        mirror.proveL2BlockHeader(
            assertionHash,
            vm.parseJsonBytes32(json, ".parentAssertionHash"),
            _afterState(),
            vm.parseJsonBytes32(json, ".inboxAcc"),
            vm.parseJsonBytes(json, ".blockHeaderRlp")
        );
    }

    function _proveTokenStorageRoot() internal {
        _proveHeader();
        mirror.proveTokenStorageRoot(assertionHash, vm.parseJsonBytesArray(json, ".accountProof"));
    }

    function _proveDelegateMappingStorageRoot() internal {
        _proveHeader();
        mirror.proveDelegateMappingStorageRoot(
            assertionHash, vm.parseJsonBytesArray(json, ".delegateMappingAccountProof")
        );
    }

    // --- checkpointAssertion ---

    function testCheckpointAssertionRecordsHash() public {
        L2StateMirror fresh = _deployMirror();
        vm.expectEmit();
        emit AssertionCheckpointed(assertionHash);
        fresh.checkpointAssertion();
        assertEq(fresh.getAssertionHashAt(block.number), assertionHash);
    }

    function testCheckpointAssertionSameBlockReverts() public {
        // setUp already checkpointed at this block
        vm.expectRevert(L2StateMirror.AssertionAlreadyCheckpointed.selector);
        mirror.checkpointAssertion();
    }

    function testCheckpointAssertionSameAssertionLaterBlockSucceeds() public {
        // state proven once serves every block the assertion is checkpointed at
        _proveTokenStorageRoot();
        mirror.proveTotalDelegation(
            assertionHash,
            vm.parseJsonBytesArray(json, ".totalDelegationLenProof"),
            vm.parseJsonBytesArray(json, ".totalDelegationLastCheckpointProof")
        );
        uint256 firstBlock = block.number;

        vm.roll(block.number + 10);
        vm.expectEmit();
        emit AssertionCheckpointed(assertionHash);
        mirror.checkpointAssertion();

        uint256 expected = vm.parseJsonUint(json, ".expectedTotalDelegation");
        assertEq(mirror.getAssertionHashAt(firstBlock), assertionHash);
        assertEq(mirror.getAssertionHashAt(block.number), assertionHash);
        assertEq(mirror.getTotalDelegationAt(firstBlock), expected);
        assertEq(mirror.getTotalDelegationAt(block.number), expected);
    }

    function testGetAssertionHashAtRevertsWhenEmpty() public {
        L2StateMirror fresh = _deployMirror();
        vm.expectRevert(L2StateMirror.NoAssertionCheckpoint.selector);
        fresh.getAssertionHashAt(block.number);
    }

    function testGetAssertionHashAtRevertsAtUncheckpointedBlock() public {
        vm.expectRevert(L2StateMirror.NoAssertionCheckpoint.selector);
        mirror.getAssertionHashAt(block.number - 1);
    }

    function testGetAssertionHashAtExactBlockOnly() public {
        // checkpoints are keyed by the exact L1 block they were committed at; queries for
        // any other block revert rather than resolving to a neighboring checkpoint
        MockRollup r = new MockRollup(keccak256("A"));
        L2StateMirror fresh = _deployMirrorWithRollup(address(r));

        vm.roll(100);
        fresh.checkpointAssertion();
        r.setLatestConfirmed(keccak256("B"));
        vm.roll(200);
        fresh.checkpointAssertion();
        r.setLatestConfirmed(keccak256("C"));
        vm.roll(300);
        fresh.checkpointAssertion();

        assertEq(fresh.getAssertionHashAt(100), keccak256("A"));
        assertEq(fresh.getAssertionHashAt(200), keccak256("B"));
        assertEq(fresh.getAssertionHashAt(300), keccak256("C"));

        uint256[4] memory uncheckpointed = [uint256(99), 150, 250, 350];
        for (uint256 i = 0; i < uncheckpointed.length; i++) {
            vm.expectRevert(L2StateMirror.NoAssertionCheckpoint.selector);
            fresh.getAssertionHashAt(uncheckpointed[i]);
        }
    }

    // --- proveL2BlockHeader ---

    function testProveL2BlockHeaderSetsStateRootAndBlockNumber() public {
        vm.expectEmit();
        emit BlockHeaderProven(
            assertionHash,
            vm.parseJsonBytes32(json, ".stateRoot"),
            vm.parseJsonUint(json, ".blockNumber")
        );
        _proveHeader();
        (, bytes32 stateRoot, uint256 blockNumber,,,) = mirror.snapshotOf(assertionHash);
        assertEq(stateRoot, vm.parseJsonBytes32(json, ".stateRoot"));
        assertEq(blockNumber, vm.parseJsonUint(json, ".blockNumber"));
    }

    function testProveL2BlockHeaderRejectsInvalidPreimage() public {
        AssertionState memory afterState = _afterState();
        // corrupt the asserted block hash so the afterState is no longer the assertion's preimage
        afterState.globalState.bytes32Vals[0] = bytes32(0);
        bytes32 computed = RollupLib.assertionHash(
            vm.parseJsonBytes32(json, ".parentAssertionHash"),
            afterState,
            vm.parseJsonBytes32(json, ".inboxAcc")
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                L2StateMirror.InvalidAssertionPreimage.selector, assertionHash, computed
            )
        );
        mirror.proveL2BlockHeader(
            assertionHash,
            vm.parseJsonBytes32(json, ".parentAssertionHash"),
            afterState,
            vm.parseJsonBytes32(json, ".inboxAcc"),
            vm.parseJsonBytes(json, ".blockHeaderRlp")
        );
    }

    function testProveL2BlockHeaderRejectsMismatchedHeader() public {
        // corrupt the header RLP so its hash no longer matches the asserted block hash
        bytes memory header = vm.parseJsonBytes(json, ".blockHeaderRlp");
        header[0] = header[0] ^ bytes1(0xff);
        vm.expectRevert(
            abi.encodeWithSelector(
                L2StateMirror.BlockHashMismatch.selector,
                keccak256(header),
                vm.parseJsonBytes32(json, ".l2BlockHash")
            )
        );
        mirror.proveL2BlockHeader(
            assertionHash,
            vm.parseJsonBytes32(json, ".parentAssertionHash"),
            _afterState(),
            vm.parseJsonBytes32(json, ".inboxAcc"),
            header
        );
    }

    function testProveL2BlockHeaderUncheckpointedReverts() public {
        vm.expectRevert(L2StateMirror.AssertionNotCheckpointed.selector);
        mirror.proveL2BlockHeader(
            keccak256("not checkpointed"),
            vm.parseJsonBytes32(json, ".parentAssertionHash"),
            _afterState(),
            vm.parseJsonBytes32(json, ".inboxAcc"),
            vm.parseJsonBytes(json, ".blockHeaderRlp")
        );
    }

    function testProveL2BlockHeaderOnlyOnce() public {
        _proveHeader();
        vm.expectRevert(L2StateMirror.AlreadyProven.selector);
        _proveHeader();
    }

    // --- getters revert before proof ---

    function testGetTotalDelegationAtRevertsBeforeProof() public {
        vm.expectRevert(L2StateMirror.TotalDelegationNotProven.selector);
        mirror.getTotalDelegationAt(block.number);
    }

    function testGetVotesAtRevertsBeforeProof() public {
        vm.expectRevert(L2StateMirror.VotesNotProven.selector);
        mirror.getVotesAt(excludeL2, block.number);
    }

    function testGetL1AddressAtRevertsBeforeProof() public {
        vm.expectRevert(L2StateMirror.L1AddressNotProven.selector);
        mirror.getL1AddressAt(delegateL2, block.number);
    }

    // --- proveTokenStorageRoot ---

    function testProveTokenStorageRootBeforeHeaderReverts() public {
        vm.expectRevert(L2StateMirror.BlockHeaderNotProven.selector);
        mirror.proveTokenStorageRoot(assertionHash, vm.parseJsonBytesArray(json, ".accountProof"));
    }

    function testProveTokenStorageRootSetsStorageRoot() public {
        _proveHeader();
        vm.expectEmit();
        emit TokenStorageRootProven(assertionHash, vm.parseJsonBytes32(json, ".storageRoot"));
        mirror.proveTokenStorageRoot(assertionHash, vm.parseJsonBytesArray(json, ".accountProof"));
        (,,, bytes32 storageRoot,,) = mirror.snapshotOf(assertionHash);
        assertEq(storageRoot, vm.parseJsonBytes32(json, ".storageRoot"));
    }

    function testProveTokenStorageRootTwiceReverts() public {
        _proveTokenStorageRoot();
        vm.expectRevert(L2StateMirror.AlreadyProven.selector);
        mirror.proveTokenStorageRoot(assertionHash, new bytes[](0));
    }

    // --- proveDelegateMappingStorageRoot ---

    function testProveDelegateMappingStorageRootBeforeHeaderReverts() public {
        vm.expectRevert(L2StateMirror.BlockHeaderNotProven.selector);
        mirror.proveDelegateMappingStorageRoot(
            assertionHash, vm.parseJsonBytesArray(json, ".delegateMappingAccountProof")
        );
    }

    function testProveDelegateMappingStorageRootSetsStorageRoot() public {
        _proveHeader();
        vm.expectEmit();
        emit DelegateMappingStorageRootProven(
            assertionHash, vm.parseJsonBytes32(json, ".delegateMappingStorageRoot")
        );
        mirror.proveDelegateMappingStorageRoot(
            assertionHash, vm.parseJsonBytesArray(json, ".delegateMappingAccountProof")
        );
        (,,,, bytes32 mappingStorageRoot,) = mirror.snapshotOf(assertionHash);
        assertEq(mappingStorageRoot, vm.parseJsonBytes32(json, ".delegateMappingStorageRoot"));
    }

    function testProveDelegateMappingStorageRootTwiceReverts() public {
        _proveDelegateMappingStorageRoot();
        vm.expectRevert(L2StateMirror.AlreadyProven.selector);
        mirror.proveDelegateMappingStorageRoot(assertionHash, new bytes[](0));
    }

    // --- proveTotalDelegation ---

    function testProveTotalDelegationBeforeStorageRootReverts() public {
        _proveHeader();
        vm.expectRevert(L2StateMirror.StorageRootNotProven.selector);
        mirror.proveTotalDelegation(assertionHash, new bytes[](0), new bytes[](0));
    }

    function testProveTotalDelegationSetsTotalDelegation() public {
        _proveTokenStorageRoot();
        vm.expectEmit();
        emit TotalDelegationProven(
            assertionHash, vm.parseJsonUint(json, ".expectedTotalDelegation")
        );
        mirror.proveTotalDelegation(
            assertionHash,
            vm.parseJsonBytesArray(json, ".totalDelegationLenProof"),
            vm.parseJsonBytesArray(json, ".totalDelegationLastCheckpointProof")
        );
        assertEq(
            mirror.getTotalDelegationAt(block.number),
            vm.parseJsonUint(json, ".expectedTotalDelegation")
        );
    }

    function testProveTotalDelegationTwiceReverts() public {
        _proveTokenStorageRoot();
        mirror.proveTotalDelegation(
            assertionHash,
            vm.parseJsonBytesArray(json, ".totalDelegationLenProof"),
            vm.parseJsonBytesArray(json, ".totalDelegationLastCheckpointProof")
        );
        vm.expectRevert(L2StateMirror.AlreadyProven.selector);
        mirror.proveTotalDelegation(assertionHash, new bytes[](0), new bytes[](0));
    }

    // --- proveVotes ---

    function testProveVotesBeforeStorageRootReverts() public {
        _proveHeader();
        vm.expectRevert(L2StateMirror.StorageRootNotProven.selector);
        mirror.proveVotes(assertionHash, excludeL2, new bytes[](0), new bytes[](0));
    }

    function testProveVotesSetsVotes() public {
        _proveTokenStorageRoot();
        vm.expectEmit();
        emit VotesProven(assertionHash, excludeL2, vm.parseJsonUint(json, ".expectedVotes"));
        mirror.proveVotes(
            assertionHash,
            excludeL2,
            vm.parseJsonBytesArray(json, ".checkpointLenProof"),
            vm.parseJsonBytesArray(json, ".lastCheckpointProof")
        );
        assertEq(
            mirror.getVotesAt(excludeL2, block.number), vm.parseJsonUint(json, ".expectedVotes")
        );
    }

    function testProveVotesForDelegateAccount() public {
        _proveTokenStorageRoot();
        mirror.proveVotes(
            assertionHash,
            delegateL2,
            vm.parseJsonBytesArray(json, ".delegateCheckpointLenProof"),
            vm.parseJsonBytesArray(json, ".delegateLastCheckpointProof")
        );
        assertEq(
            mirror.getVotesAt(delegateL2, block.number),
            vm.parseJsonUint(json, ".expectedDelegateVotes")
        );
    }

    function testProveVotesTwiceReverts() public {
        _proveTokenStorageRoot();
        mirror.proveVotes(
            assertionHash,
            excludeL2,
            vm.parseJsonBytesArray(json, ".checkpointLenProof"),
            vm.parseJsonBytesArray(json, ".lastCheckpointProof")
        );
        vm.expectRevert(L2StateMirror.AlreadyProven.selector);
        mirror.proveVotes(assertionHash, excludeL2, new bytes[](0), new bytes[](0));
    }

    // --- proveL1Address ---

    function testProveL1AddressBeforeMappingStorageRootReverts() public {
        _proveHeader();
        vm.expectRevert(L2StateMirror.DelegateMappingStorageRootNotProven.selector);
        mirror.proveL1Address(assertionHash, delegateL2, new bytes[](0));
    }

    function testProveL1AddressSetsL1Address() public {
        _proveDelegateMappingStorageRoot();
        vm.expectEmit();
        emit L1AddressProven(
            assertionHash, delegateL2, vm.parseJsonAddress(json, ".expectedDelegateL1Address")
        );
        mirror.proveL1Address(
            assertionHash, delegateL2, vm.parseJsonBytesArray(json, ".delegateL1AddressProof")
        );
        assertEq(
            mirror.getL1AddressAt(delegateL2, block.number),
            vm.parseJsonAddress(json, ".expectedDelegateL1Address")
        );
    }

    function testProveL1AddressTwiceReverts() public {
        _proveDelegateMappingStorageRoot();
        mirror.proveL1Address(
            assertionHash, delegateL2, vm.parseJsonBytesArray(json, ".delegateL1AddressProof")
        );
        vm.expectRevert(L2StateMirror.AlreadyProven.selector);
        mirror.proveL1Address(assertionHash, delegateL2, new bytes[](0));
    }

    // --- claimL1AddressBySig ---

    function _claimSig(uint256 signerKey, bytes32 _assertionHash, address l1Address)
        internal
        view
        returns (bytes memory)
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("L2StateMirror")),
                keccak256(bytes("1")),
                block.chainid,
                address(mirror)
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(abi.encode(mirror.CLAIM_L1_ADDRESS_TYPEHASH(), _assertionHash, l1Address))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function testDomainSeparatorNamesTheProxy() public {
        bytes32 expected = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("L2StateMirror")),
                keccak256(bytes("1")),
                block.chainid,
                address(mirror)
            )
        );
        assertEq(mirror.DOMAIN_SEPARATOR(), expected);
    }

    function testClaimL1AddressBySigSetsL1Address() public {
        vm.expectEmit();
        emit L1AddressClaimedBySig(assertionHash, eoaDelegate, eoaL1Address);
        mirror.claimL1AddressBySig(
            assertionHash,
            eoaDelegate,
            eoaL1Address,
            _claimSig(eoaDelegateKey, assertionHash, eoaL1Address)
        );
        assertEq(mirror.getL1AddressAt(eoaDelegate, block.number), eoaL1Address);
    }

    function testClaimL1AddressBySigUncheckpointedReverts() public {
        bytes32 other = keccak256("not checkpointed");
        bytes memory sig = _claimSig(eoaDelegateKey, other, eoaL1Address);
        vm.expectRevert(L2StateMirror.AssertionNotCheckpointed.selector);
        mirror.claimL1AddressBySig(other, eoaDelegate, eoaL1Address, sig);
    }

    function testClaimL1AddressBySigZeroL1AddressReverts() public {
        bytes memory sig = _claimSig(eoaDelegateKey, assertionHash, address(0));
        vm.expectRevert(L2StateMirror.ZeroL1Address.selector);
        mirror.claimL1AddressBySig(assertionHash, eoaDelegate, address(0), sig);
    }

    function testClaimL1AddressBySigWrongSignerReverts() public {
        bytes memory sig = _claimSig(0xB0B, assertionHash, eoaL1Address);
        vm.expectRevert(L2StateMirror.InvalidSignature.selector);
        mirror.claimL1AddressBySig(assertionHash, eoaDelegate, eoaL1Address, sig);
    }

    function testClaimL1AddressBySigWrongAssertionReverts() public {
        // signature binds the assertion hash; reusing it for another assertion fails
        MockRollup r = new MockRollup(keccak256("other"));
        L2StateMirror fresh = _deployMirrorWithRollup(address(r));
        vm.roll(100);
        fresh.checkpointAssertion();
        r.setLatestConfirmed(keccak256("other2"));
        vm.roll(200);
        fresh.checkpointAssertion();

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("L2StateMirror")),
                keccak256(bytes("1")),
                block.chainid,
                address(fresh)
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(fresh.CLAIM_L1_ADDRESS_TYPEHASH(), keccak256("other"), eoaL1Address)
                )
            )
        );
        (uint8 v, bytes32 r_, bytes32 s) = vm.sign(eoaDelegateKey, digest);
        bytes memory sig = abi.encodePacked(r_, s, v);

        fresh.claimL1AddressBySig(keccak256("other"), eoaDelegate, eoaL1Address, sig);
        vm.expectRevert(L2StateMirror.InvalidSignature.selector);
        fresh.claimL1AddressBySig(keccak256("other2"), eoaDelegate, eoaL1Address, sig);
    }

    function testClaimL1AddressBySigWrongL1AddressReverts() public {
        // signature binds the l1 address; submitting a different one fails
        bytes memory sig = _claimSig(eoaDelegateKey, assertionHash, eoaL1Address);
        vm.expectRevert(L2StateMirror.InvalidSignature.selector);
        mirror.claimL1AddressBySig(assertionHash, eoaDelegate, address(0xDEAD), sig);
    }

    function testClaimL1AddressBySigTwiceReverts() public {
        bytes memory sig = _claimSig(eoaDelegateKey, assertionHash, eoaL1Address);
        mirror.claimL1AddressBySig(assertionHash, eoaDelegate, eoaL1Address, sig);
        vm.expectRevert(L2StateMirror.AlreadyProven.selector);
        mirror.claimL1AddressBySig(assertionHash, eoaDelegate, eoaL1Address, sig);
    }

    function testClaimL1AddressBySigAfterProveReverts() public {
        _proveDelegateMappingStorageRoot();
        mirror.proveL1Address(
            assertionHash, delegateL2, vm.parseJsonBytesArray(json, ".delegateL1AddressProof")
        );
        vm.expectRevert(L2StateMirror.AlreadyProven.selector);
        mirror.claimL1AddressBySig(assertionHash, delegateL2, eoaL1Address, "");
    }

    function testProveL1AddressAfterClaimReverts() public {
        _proveDelegateMappingStorageRoot();
        mirror.claimL1AddressBySig(
            assertionHash,
            eoaDelegate,
            eoaL1Address,
            _claimSig(eoaDelegateKey, assertionHash, eoaL1Address)
        );
        vm.expectRevert(L2StateMirror.AlreadyProven.selector);
        mirror.proveL1Address(assertionHash, eoaDelegate, new bytes[](0));
    }

    // --- checkpointAssertion with an unreachable rollup ---

    function testCheckpointAssertionRollupRevertsNoCacheReverts() public {
        L2StateMirror m = _deployMirrorWithRollup(address(new RevertingRollup()));
        vm.expectRevert(L2StateMirror.NoAssertionCheckpoint.selector);
        m.checkpointAssertion();
    }

    function testCheckpointAssertionRollupShortDataNoCacheReverts() public {
        L2StateMirror m = _deployMirrorWithRollup(address(new ShortReturnRollup()));
        vm.expectRevert(L2StateMirror.NoAssertionCheckpoint.selector);
        m.checkpointAssertion();
    }

    function testCheckpointAssertionZeroLatestUsesCache() public {
        // setUp checkpointed the real assertion; a successfully returned zero hash is treated
        // as unreachable and the fallback commits the cached assertion
        rollup.setLatestConfirmed(bytes32(0));
        vm.roll(block.number + 1);
        vm.expectEmit();
        emit AssertionCheckpointed(assertionHash);
        mirror.checkpointAssertion();
        assertEq(mirror.getAssertionHashAt(block.number), assertionHash);
        assertEq(mirror.lastSeenLatestConfirmedAssertion(), assertionHash);
    }

    function testCheckpointAssertionUnconfirmedLatestUsesCache() public {
        // a latestConfirmed value the rollup does not also record as a Confirmed assertion is
        // treated as unreachable: the fallback commits the cached assertion, which stays clean
        rollup.setLatestConfirmed(keccak256("evil"));
        rollup.setStatus(keccak256("evil"), AssertionStatus.Pending);
        vm.roll(block.number + 1);
        mirror.checkpointAssertion();
        assertEq(mirror.getAssertionHashAt(block.number), assertionHash);
        assertEq(mirror.lastSeenLatestConfirmedAssertion(), assertionHash);
    }

    function testCheckpointAssertionUnconfirmedLatestNoCacheReverts() public {
        MockRollup r = new MockRollup(keccak256("evil"));
        r.setStatus(keccak256("evil"), AssertionStatus.NoAssertion);
        L2StateMirror fresh = _deployMirrorWithRollup(address(r));
        vm.expectRevert(L2StateMirror.NoAssertionCheckpoint.selector);
        fresh.checkpointAssertion();
    }

    function testCheckpointAssertionFallbackUsesLatestSeen() public {
        MockRollup r = new MockRollup(keccak256("A"));
        L2StateMirror fresh = _deployMirrorWithRollup(address(r));
        fresh.checkpointAssertion();

        r.setLatestConfirmed(keccak256("B"));
        vm.roll(block.number + 1);
        fresh.checkpointAssertion();
        assertEq(fresh.lastSeenLatestConfirmedAssertion(), keccak256("B"));

        // rollup becomes unreachable; the fallback commits the latest seen assertion
        vm.etch(address(r), address(new RevertingRollup()).code);
        vm.roll(block.number + 1);
        fresh.checkpointAssertion();
        assertEq(fresh.getAssertionHashAt(block.number), keccak256("B"));
    }
}
