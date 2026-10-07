// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../src/l1-voting/ProofHelper.sol";

contract ProofHelperTest is Test {
    ProofHelper helper;
    string json;

    function setUp() public {
        helper = new ProofHelper();
        json = vm.readFile(string.concat(vm.projectRoot(), "/test/l1-voting/fixtures/proof_helper.json"));
    }

    function testCalculatesBlockHash() public {
        assertEq(
            helper.calculateBlockHash(vm.parseJsonBytes(json, ".blockHeaderRlp")), vm.parseJsonBytes32(json, ".blockHash")
        );
    }

    function testExtractsStateRoot() public {
        assertEq(
            helper.extractStateRootFromHeader(vm.parseJsonBytes(json, ".blockHeaderRlp")),
            vm.parseJsonBytes32(json, ".stateRoot")
        );
    }

    function testExtractsBlockNumber() public {
        assertEq(
            helper.extractBlockNumberFromHeader(vm.parseJsonBytes(json, ".blockHeaderRlp")),
            vm.parseJsonUint(json, ".blockNumber")
        );
    }

    function testStateRootValueExceeding32BytesReverts() public {
        bytes memory header =
            abi.encodePacked(hex"ea808080a1", bytes32(type(uint256).max), bytes1(0xff), hex"8080808080");
        vm.expectRevert("ProofHelper: rlp value exceeds 32 bytes");
        helper.extractStateRootFromHeader(header);
    }

    function testBlockNumberValueExceeding32BytesReverts() public {
        bytes memory header =
            abi.encodePacked(hex"ea8080808080808080a1", bytes32(type(uint256).max), bytes1(0xff));
        vm.expectRevert("ProofHelper: rlp value exceeds 32 bytes");
        helper.extractBlockNumberFromHeader(header);
    }

    function testVerifiesAccountProof() public {
        bytes32 storageRoot = helper.checkAccountProof(
            vm.parseJsonBytes32(json, ".stateRoot"),
            vm.parseJsonAddress(json, ".account"),
            vm.parseJsonBytesArray(json, ".accountProof")
        );
        assertEq(storageRoot, vm.parseJsonBytes32(json, ".storageRoot"));
    }

    function testVerifiesStorageProofs() public {
        bytes32 storageRoot = vm.parseJsonBytes32(json, ".storageRoot");
        assertEq(
            helper.checkStorageProof(storageRoot, vm.parseJsonUint(json, ".slot0"), vm.parseJsonBytesArray(json, ".slot0Proof")),
            vm.parseJsonUint(json, ".slot0Value")
        );
        assertEq(
            helper.checkStorageProof(storageRoot, vm.parseJsonUint(json, ".slot1"), vm.parseJsonBytesArray(json, ".slot1Proof")),
            vm.parseJsonUint(json, ".slot1Value")
        );
    }

    // A never-written slot / nonexistent account is absent from the trie, so eth_getProof returns
    // an exclusion proof; the inclusion-only trie must revert rather than report zero (fail
    // closed). The revert reason depends on where the key's path dies in the trie, so it is not
    // pinned.

    function testZeroSlotUnprovable() public {
        vm.expectRevert();
        helper.checkStorageProof(
            vm.parseJsonBytes32(json, ".storageRoot"),
            vm.parseJsonUint(json, ".zeroSlot"),
            vm.parseJsonBytesArray(json, ".zeroSlotProof")
        );
    }

    function testAbsentAccountUnprovable() public {
        vm.expectRevert();
        helper.checkAccountProof(
            vm.parseJsonBytes32(json, ".stateRoot"),
            vm.parseJsonAddress(json, ".absentAccount"),
            vm.parseJsonBytesArray(json, ".absentAccountProof")
        );
    }

    function testCalculatesSlots() public {
        uint256 mSlot =
            helper.mappingSlot(vm.parseJsonUint(json, ".delegateCheckpointsSlot"), vm.parseJsonAddress(json, ".excludeAddress"));
        assertEq(mSlot, vm.parseJsonUint(json, ".expectedMappingSlot"));

        uint256 vSlot = helper.arraySlot(mSlot, vm.parseJsonUint(json, ".checkpointsLength") - 1);
        assertEq(vSlot, vm.parseJsonUint(json, ".expectedArraySlot"));
    }
}
