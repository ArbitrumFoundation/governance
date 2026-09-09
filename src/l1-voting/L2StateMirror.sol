// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IRollupCore, AssertionState} from "@arbitrum/nitro-contracts/src/rollup/IRollupCore.sol";
import {AssertionStatus} from "@arbitrum/nitro-contracts/src/rollup/Assertion.sol";
import {ExcessivelySafeCall} from "excessively-safe-call/ExcessivelySafeCall.sol";
import {RollupLib} from "@arbitrum/nitro-contracts/src/rollup/RollupLib.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import {ProofHelper} from "./ProofHelper.sol";

/// @notice Accepts proofs of L2 governance state (ARB token voting power and L2 DelegateMapping
///         claims) against confirmed assertions and serves it on L1, checkpointed by the L1
///         block at which each assertion was committed. EOA delegates may claim their L1 address
///         with an EIP-712 signature instead of an L2 claim and proof.
/// @dev    The L2StateMirror should continue to function even if the rollup itself is broken or
///         the assertion chain is not progressing. This keeps the entire L1 voting system
///         isolated from certain issues in the chain's main contracts.
contract L2StateMirror is EIP712 {
    using ExcessivelySafeCall for address;

    /// @notice Per-assertion mirrored L2 state, populated by the prove* functions.
    struct L2Snapshot {
        bool exists;
        bytes32 l2StateRoot;
        /// @dev Not read on chain. Tells provers which L2 block to build their eth_getProof
        ///      proofs against for this assertion.
        uint256 l2BlockNumber;
        bytes32 l2TokenStorageRoot;
        bytes32 l2DelegateMappingStorageRoot;
        uint256 totalDelegation;
        mapping(address => uint256) votesOf;
        mapping(address => address) l1AddressOf;
    }

    /// @notice Proof helper contract
    ProofHelper public immutable proofHelper;
    /// @notice L2 ARB token address
    address public immutable l2TokenAddress;
    /// @notice L2 ARB token per-delegate vote checkpoints slot
    uint256 public immutable l2DelegateCheckpointsSlot;
    /// @notice L2 ARB token total delegation checkpoints slot
    uint256 public immutable l2TokenTotalDelegationSlot;
    /// @notice DelegateMapping address on L2
    address public immutable l2DelegateMappingAddress;
    /// @notice L2 DelegateMapping delegate-to-L1-address mapping slot
    uint256 public immutable l2DelegateMappingL1AddressSlot;
    /// @notice Rollup contract on L1
    IRollupCore public immutable rollup;

    /// @dev Bounds on the gas {_tryRollupCall} forwards to the rollup. Measured on the live ARB1
    ///      rollup with cold state, latestConfirmed costs ~13k gas and getAssertion ~16k.
    ///      The floor is the gas that must be left before the rollup is queried at all; EIP-150
    ///      forwards 63/64 of it, still many times the real cost, so a caller cannot starve a
    ///      healthy rollup into looking unreachable. The ceiling bounds what a rollup that burns
    ///      gas can consume, so it cannot take the whole transaction down with it.
    uint256 internal constant ROLLUP_CALL_GAS_FLOOR = 200_000;
    uint256 internal constant ROLLUP_CALL_GAS_CEIL = 500_000;

    /// @notice EIP-712 typehash of the struct signed for {claimL1AddressBySig}
    bytes32 public constant CLAIM_L1_ADDRESS_TYPEHASH =
        keccak256("ClaimL1Address(bytes32 assertionHash,address l1Address)");

    /// @notice The latest confirmed assertion hash seen by this contract.
    bytes32 public lastSeenLatestConfirmedAssertion;

    /// @notice Mirrored L2 state proven for each confirmed assertion hash.
    mapping(bytes32 => L2Snapshot) public snapshotOf;

    /// @dev Internal mapping of assertion checkpoints
    mapping(uint256 => bytes32) _blockNumberToAssertion;

    /// @notice Event emitted when a confirmed assertion is committed to the checkpoint history
    event AssertionCheckpointed(bytes32 indexed assertionHash);
    /// @notice Event emitted when the L2 block header is proven
    event BlockHeaderProven(
        bytes32 indexed assertionHash, bytes32 l2StateRoot, uint256 l2BlockNumber
    );
    /// @notice Event emitted when the storage root of the L2 ARB token is proven
    event TokenStorageRootProven(bytes32 indexed assertionHash, bytes32 l2TokenStorageRoot);
    /// @notice Event emitted when the storage root of the L2 DelegateMapping is proven
    event DelegateMappingStorageRootProven(
        bytes32 indexed assertionHash, bytes32 l2DelegateMappingStorageRoot
    );
    /// @notice Event emitted when the total delegation of the L2 ARB token is proven
    event TotalDelegationProven(bytes32 indexed assertionHash, uint256 totalDelegation);
    /// @notice Event emitted when the votes of an account are proven
    event VotesProven(bytes32 indexed assertionHash, address indexed account, uint256 votes);
    /// @notice Event emitted when a delegate's claimed L1 address is proven
    event L1AddressProven(
        bytes32 indexed assertionHash, address indexed l2Delegate, address indexed l1Address
    );
    /// @notice Event emitted when a delegate claims an L1 address by signature
    event L1AddressClaimedBySig(
        bytes32 indexed assertionHash, address indexed l2Delegate, address indexed l1Address
    );

    error AlreadyProven();
    error InvalidSignature();
    error ZeroL1Address();
    error AssertionAlreadyCheckpointed();
    error AssertionNotCheckpointed();
    error NoAssertionCheckpoint();
    error InvalidAssertionPreimage(bytes32 assertionHash, bytes32 computedAssertionHash);
    error BlockHashMismatch(bytes32 fromHeader, bytes32 fromAssertion);
    error BlockHeaderNotProven();
    error StorageRootNotProven();
    error DelegateMappingStorageRootNotProven();
    error TotalDelegationNotProven();
    error VotesNotProven();
    error L1AddressNotProven();
    error GasTooLowForRollupCall();

    constructor(
        address _proofHelper,
        address _l2TokenAddress,
        uint256 _l2DelegateCheckpointsSlot,
        uint256 _l2TokenTotalDelegationSlot,
        address _l2DelegateMappingAddress,
        uint256 _l2DelegateMappingL1AddressSlot,
        address _rollup
    ) EIP712("L2StateMirror", "1") {
        proofHelper = ProofHelper(_proofHelper);
        l2TokenAddress = _l2TokenAddress;
        l2DelegateCheckpointsSlot = _l2DelegateCheckpointsSlot;
        l2TokenTotalDelegationSlot = _l2TokenTotalDelegationSlot;
        l2DelegateMappingAddress = _l2DelegateMappingAddress;
        l2DelegateMappingL1AddressSlot = _l2DelegateMappingL1AddressSlot;
        rollup = IRollupCore(_rollup);
    }

    /// @notice Permissionlessly commit either the rollup's latest confirmed assertion if available,
    ///         or this contract's cached latest confirmed assertion. The assertion is committed to
    ///         block.number. If block.number has already been checkpointed, revert.
    function checkpointAssertion() external {
        if (_blockNumberToAssertion[block.number] != 0) {
            revert AssertionAlreadyCheckpointed();
        }

        bytes32 latest = _tryGetLatestConfirmedAssertion();
        if (latest == 0) {
            latest = lastSeenLatestConfirmedAssertion;
        } else if (latest != lastSeenLatestConfirmedAssertion) {
            lastSeenLatestConfirmedAssertion = latest;
        }

        // rollup unreachable and no assertion ever seen
        if (latest == 0) {
            revert NoAssertionCheckpoint();
        }

        _blockNumberToAssertion[block.number] = latest;
        snapshotOf[latest].exists = true;
        emit AssertionCheckpointed(latest);
    }

    /// @notice Set the L2 state root and block number corresponding to a confirmed assertion
    function proveL2BlockHeader(
        bytes32 assertionHash,
        bytes32 parentAssertionHash,
        AssertionState memory afterState,
        bytes32 inboxAcc,
        bytes memory blockHeaderRlpBytes
    ) external {
        L2Snapshot storage snapshot = snapshotOf[assertionHash];
        if (!snapshot.exists) {
            revert AssertionNotCheckpointed();
        }
        if (snapshot.l2StateRoot != 0) {
            revert AlreadyProven();
        }

        bytes32 computedAssertionHash =
            RollupLib.assertionHash(parentAssertionHash, afterState, inboxAcc);
        if (assertionHash != computedAssertionHash) {
            revert InvalidAssertionPreimage(assertionHash, computedAssertionHash);
        }

        bytes32 assertionBlockHash = afterState.globalState.bytes32Vals[0];
        bytes32 blockHeaderHash = proofHelper.calculateBlockHash(blockHeaderRlpBytes);
        if (blockHeaderHash != assertionBlockHash) {
            revert BlockHashMismatch(blockHeaderHash, assertionBlockHash);
        }

        snapshot.l2StateRoot = proofHelper.extractStateRootFromHeader(blockHeaderRlpBytes);
        snapshot.l2BlockNumber = proofHelper.extractBlockNumberFromHeader(blockHeaderRlpBytes);

        emit BlockHeaderProven(assertionHash, snapshot.l2StateRoot, snapshot.l2BlockNumber);
    }

    /// @notice Prove the storage root of the L2 ARB token
    function proveTokenStorageRoot(bytes32 assertionHash, bytes[] memory accountProof) external {
        L2Snapshot storage snapshot = snapshotOf[assertionHash];
        if (snapshot.l2TokenStorageRoot != 0) {
            revert AlreadyProven();
        }
        if (snapshot.l2StateRoot == 0) {
            revert BlockHeaderNotProven();
        }

        snapshot.l2TokenStorageRoot =
            proofHelper.checkAccountProof(snapshot.l2StateRoot, l2TokenAddress, accountProof);

        emit TokenStorageRootProven(assertionHash, snapshot.l2TokenStorageRoot);
    }

    /// @notice Prove the storage root of the L2 DelegateMapping
    function proveDelegateMappingStorageRoot(bytes32 assertionHash, bytes[] memory accountProof)
        external
    {
        L2Snapshot storage snapshot = snapshotOf[assertionHash];
        if (snapshot.l2DelegateMappingStorageRoot != 0) {
            revert AlreadyProven();
        }
        if (snapshot.l2StateRoot == 0) {
            revert BlockHeaderNotProven();
        }

        snapshot.l2DelegateMappingStorageRoot = proofHelper.checkAccountProof(
            snapshot.l2StateRoot, l2DelegateMappingAddress, accountProof
        );

        emit DelegateMappingStorageRootProven(assertionHash, snapshot.l2DelegateMappingStorageRoot);
    }

    /// @notice Prove the total delegation of the L2 ARB token
    function proveTotalDelegation(
        bytes32 assertionHash,
        bytes[] memory checkpointLenStorageProof,
        bytes[] memory lastCheckpointStorageProof
    ) external {
        L2Snapshot storage snapshot = snapshotOf[assertionHash];
        if (snapshot.totalDelegation != 0) {
            revert AlreadyProven();
        }
        if (snapshot.l2TokenStorageRoot == 0) {
            revert StorageRootNotProven();
        }

        uint256 totalDelegation = _proveLastItemInCheckpointsArray(
            snapshot.l2TokenStorageRoot,
            l2TokenTotalDelegationSlot,
            checkpointLenStorageProof,
            lastCheckpointStorageProof
        );
        snapshot.totalDelegation = totalDelegation;

        emit TotalDelegationProven(assertionHash, totalDelegation);
    }

    /// @notice Prove the votes of an account
    function proveVotes(
        bytes32 assertionHash,
        address account,
        bytes[] memory checkpointLenStorageProof,
        bytes[] memory lastCheckpointStorageProof
    ) external {
        L2Snapshot storage snapshot = snapshotOf[assertionHash];
        if (snapshot.votesOf[account] != 0) {
            revert AlreadyProven();
        }
        if (snapshot.l2TokenStorageRoot == 0) {
            revert StorageRootNotProven();
        }

        uint256 checkpointArrSlot = proofHelper.mappingSlot(l2DelegateCheckpointsSlot, account);
        uint256 votes = _proveLastItemInCheckpointsArray(
            snapshot.l2TokenStorageRoot,
            checkpointArrSlot,
            checkpointLenStorageProof,
            lastCheckpointStorageProof
        );
        snapshot.votesOf[account] = votes;

        emit VotesProven(assertionHash, account, votes);
    }

    /// @notice Prove the L1 voting address an L2 delegate has claimed in the L2 DelegateMapping
    /// @dev    A delegate that never claimed (or claimed the zero address) has a zero slot,
    ///         which is unprovable: the OP trie verifies inclusion only.
    function proveL1Address(bytes32 assertionHash, address l2Delegate, bytes[] memory storageProof)
        external
    {
        L2Snapshot storage snapshot = snapshotOf[assertionHash];
        if (snapshot.l1AddressOf[l2Delegate] != address(0)) {
            revert AlreadyProven();
        }
        if (snapshot.l2DelegateMappingStorageRoot == 0) {
            revert DelegateMappingStorageRootNotProven();
        }

        uint256 slot = proofHelper.mappingSlot(l2DelegateMappingL1AddressSlot, l2Delegate);
        address l1Address = address(
            uint160(
                proofHelper.checkStorageProof(
                    snapshot.l2DelegateMappingStorageRoot, slot, storageProof
                )
            )
        );
        snapshot.l1AddressOf[l2Delegate] = l1Address;

        emit L1AddressProven(assertionHash, l2Delegate, l1Address);
    }

    /// @notice Claim the L1 voting address for an EOA delegate with an EIP-712 signature from the
    ///         delegate, instead of an L2 DelegateMapping claim and proof.
    /// @dev    The signed struct binds the assertion hash, so a signature is valid for one
    ///         snapshot only. The delegate is recovered from the signature rather than signed
    ///         over. Reverts if an address was already proven or claimed for this delegate and
    ///         assertion.
    /// @dev    The struct carries no nonce or deadline and there is no cancel hook.
    function claimL1AddressBySig(
        bytes32 assertionHash,
        address l2Delegate,
        address l1Address,
        bytes calldata signature
    ) external {
        L2Snapshot storage snapshot = snapshotOf[assertionHash];
        if (!snapshot.exists) {
            revert AssertionNotCheckpointed();
        }
        if (snapshot.l1AddressOf[l2Delegate] != address(0)) {
            revert AlreadyProven();
        }
        if (l1Address == address(0)) {
            revert ZeroL1Address();
        }

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(CLAIM_L1_ADDRESS_TYPEHASH, assertionHash, l1Address))
        );
        if (ECDSA.recover(digest, signature) != l2Delegate) {
            revert InvalidSignature();
        }

        snapshot.l1AddressOf[l2Delegate] = l1Address;

        emit L1AddressClaimedBySig(assertionHash, l2Delegate, l1Address);
    }

    /// @notice EIP-712 domain separator to sign {claimL1AddressBySig} messages against
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @dev Proves the value held in the last checkpoint of an ARB token checkpoints array, given the
    ///      slot holding the array length. Shared by votes and total delegation, which use the same OZ
    ///      checkpoint layout: fromBlock in the low 32 bits, value in the high 224, so the value is
    ///      recovered by shifting off the low 32 bits.
    /// @dev An empty array is unprovable and reverts: the OP trie verifies inclusion only, so the zero
    ///      length slot is an exclusion proof. A non-empty array's last checkpoint slot is always
    ///      nonzero (fromBlock is nonzero) even when the value is 0, so it stays provable.
    function _proveLastItemInCheckpointsArray(
        bytes32 storageRoot,
        uint256 checkpointArrSlot,
        bytes[] memory checkpointLenStorageProof,
        bytes[] memory lastCheckpointStorageProof
    ) private view returns (uint256) {
        uint256 checkpointsLen =
            proofHelper.checkStorageProof(storageRoot, checkpointArrSlot, checkpointLenStorageProof);
        uint256 lastCheckpointSlot = proofHelper.arraySlot(checkpointArrSlot, checkpointsLen - 1);
        uint256 lastCheckpoint = proofHelper.checkStorageProof(
            storageRoot, lastCheckpointSlot, lastCheckpointStorageProof
        );

        // right shift to drop the fromBlock, leaving the checkpoint value
        return lastCheckpoint >> 32;
    }

    /// @notice Get the confirmed assertion hash committed to an L1 block number
    /// @dev    Reverts if no checkpoint exists at the given block
    function getAssertionHashAt(uint256 blockNumber) public view returns (bytes32) {
        bytes32 assertionHash = _blockNumberToAssertion[blockNumber];
        if (assertionHash == bytes32(0)) {
            revert NoAssertionCheckpoint();
        }
        return assertionHash;
    }

    /// @notice Get the total delegation of the L2 ARB token proven for the assertion committed as of an L1 block
    /// @dev    If the total delegation is zero, the proof has not been provided and the function will revert
    function getTotalDelegationAt(uint256 blockNumber) external view returns (uint256) {
        uint256 _totalDelegation = snapshotOf[getAssertionHashAt(blockNumber)].totalDelegation;
        if (_totalDelegation == 0) {
            revert TotalDelegationNotProven();
        }
        return _totalDelegation;
    }

    /// @notice Get the voting power proven for an L2 account as of an L1 block
    /// @dev    If the voting power is zero or unproven the function will revert
    function getVotesAt(address l2Account, uint256 blockNumber) external view returns (uint256) {
        uint256 votes = snapshotOf[getAssertionHashAt(blockNumber)].votesOf[l2Account];
        if (votes == 0) {
            revert VotesNotProven();
        }
        return votes;
    }

    /// @notice Get the L1 voting address proven for an L2 delegate as of an L1 block
    /// @dev    If the claim is zero or unproven the function will revert
    function getL1AddressAt(address l2Delegate, uint256 blockNumber)
        external
        view
        returns (address)
    {
        address l1Address = snapshotOf[getAssertionHashAt(blockNumber)].l1AddressOf[l2Delegate];
        if (l1Address == address(0)) {
            revert L1AddressNotProven();
        }
        return l1Address;
    }

    /// @dev Attempt to fetch the rollup's latest confirmed assertion.
    ///      Never reverts on anything the rollup does, but does revert with
    ///      GasTooLowForRollupCall if the caller left too little gas to query it properly.
    ///      Returns rollup.latestConfirmed() iff it returns exactly 32 bytes and does not revert,
    ///      and rollup.getAssertion(latestConfirmed).status == AssertionStatus.Confirmed.
    ///      Otherwise returns 0.
    ///      The getAssertion check attempts to guard against a buggy rollup returning
    ///      incorrect data from storage, eg because of a storage layout issue in the rollup.
    function _tryGetLatestConfirmedAssertion() internal view returns (bytes32) {
        (bool ok, bytes memory ret) =
            _tryRollupCall(abi.encodeCall(IRollupCore.latestConfirmed, ()), 32);
        if (!ok) {
            return 0;
        }
        bytes32 latest = abi.decode(ret, (bytes32));
        if (latest == 0) {
            return 0;
        }

        (ok, ret) = _tryRollupCall(abi.encodeCall(IRollupCore.getAssertion, (latest)), 192);
        if (!ok) {
            return 0;
        }
        // AssertionNode is a tuple of 6 words with status as the fifth
        uint256[6] memory node = abi.decode(ret, (uint256[6]));
        if (node[4] != uint256(AssertionStatus.Confirmed)) {
            return 0;
        }
        return latest;
    }

    /// @dev Staticcall the rollup with bounded gas, requiring exactly retSize bytes of
    ///      returndata. One extra byte is copied so an oversized response is detectable;
    ///      ok is false if the call reverted or returned any size other than retSize.
    function _tryRollupCall(bytes memory data, uint8 retSize)
        internal
        view
        returns (bool ok, bytes memory ret)
    {
        if (gasleft() < ROLLUP_CALL_GAS_FLOOR) {
            revert GasTooLowForRollupCall();
        }
        (ok, ret) =
            address(rollup).excessivelySafeStaticCall(ROLLUP_CALL_GAS_CEIL, retSize + 1, data);
        ok = ok && ret.length == retSize;
    }
}
