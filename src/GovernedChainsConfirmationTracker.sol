// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./BoldIfaces.sol";
import "./interfaces/IGovernedChainsConfirmationTracker.sol";

/// @notice Deployed on a parent chain to track some number of child chains.
/// Tracks the parent chain block number up through which all messages are guaranteed
/// to be confirmed (and thus, e.g., child-to-parent message are executable)
/// for each tracked child chain.
contract GovernedChainsConfirmationTracker is Ownable, IGovernedChainsConfirmationTracker {
    /// @notice Array of all tracked chains
    ChainInfo[] public chains;
    /// @notice length of chains, for ease of client queries
    uint256 immutable chainsLength;

    /// @notice Data stored for each tracked chain
    struct ChainInfo {
        uint256 chainId; // child chain's chain id (for convenience / readability)
        address rollupAddress; // address of child-chain's core Rollup contract
        uint256 messagesConfirmedParentBlock; // Parent block number up through which this contract guarantees all messages are confirmed
    }

    event MessagesConfirmedBlockUpdated(
        uint256 blockNum, uint256 indexed chainId, bool indexed isForceUpdate
    );

    error NotAdvanced(uint256 currentBlock, uint256 messagesConfirmedParentBlock, uint256 chainId);
    error NotAContract(address addr);
    error AssertionNotConfirmed(bytes32 assertionHash, AssertionStatus assertionStatus);
    error DuplicateAssertion(bytes32 assertionHash);

    /// @param _chains Data for all tracked chains
    /// @param _owner Address with affordance to trigger a force-update
    constructor(ChainInfo[] memory _chains, address _owner) {
        for (uint256 i = 0; i < _chains.length; i++) {
            if (!Address.isContract(_chains[i].rollupAddress)) {
                revert NotAContract(_chains[i].rollupAddress);
            }
            chains.push(_chains[i]);
        }
        chainsLength = chains.length;
        transferOwnership(_owner);
    }

    /// @notice Get parent chain block number up through which messages from
    /// target child chain are guaranteed confirmed.
    /// @dev The core Arbitrum contracts guarantee that once a message is included in the inbox,
    /// it will be included in the assertion after the next assertion; thus, this method requires
    /// two confirmed assertion hashes.
    /// @param _chainIndex The index in chains of the target chain.
    /// @param _assertionHashes Hashes of two confirmed target chain assertions. The older of the two
    /// assertions is used to calculate the return value.
    function getMessagesConfirmedParentChainBlock(
        uint256 _chainIndex,
        bytes32[2] memory _assertionHashes
    ) public view returns (uint256) {
        if (_assertionHashes[0] == _assertionHashes[1]) {
            revert DuplicateAssertion(_assertionHashes[0]);
        }

        ChainInfo memory chainInfo = chains[_chainIndex];
        address rollupAddress = chainInfo.rollupAddress;
        AssertionNode[2] memory assertions;
        assertions[0] = IRollup(rollupAddress).getAssertion(_assertionHashes[0]);
        assertions[1] = IRollup(rollupAddress).getAssertion(_assertionHashes[1]);

        // ensure both assertions are confirmed
        for (uint256 i = 0; i < assertions.length; i++) {
            if (assertions[i].status != AssertionStatus.Confirmed) {
                revert AssertionNotConfirmed({
                    assertionHash: _assertionHashes[i],
                    assertionStatus: assertions[i].status
                });
            }
        }
        // Get the creation block of the older of the two assertion.
        uint256 minL1AssertedBlock = assertions[0].createdAtBlock < assertions[1].createdAtBlock
            ? assertions[0].createdAtBlock
            : assertions[1].createdAtBlock;
        // Subtract one to avoid the edge case of a message included after an assertion in the same block.
        return minL1AssertedBlock - 1;
    }

    /// @notice Update the recorded parent chain block number up through which messages from
    /// target child chain are guaranteed confirmed (uses getMessagesConfirmedParentChainBlock).
    /// @param _chainIndex The index in chains of the target chain.
    /// @param _assertionHashes Hashes of two confirmed target chain assertions.
    function updateMessagesConfirmedParentChainBlock(
        uint256 _chainIndex,
        bytes32[2] memory _assertionHashes
    ) external {
        ChainInfo storage chainInfo = chains[_chainIndex];

        uint256 minL1AssertedBlock =
            getMessagesConfirmedParentChainBlock(_chainIndex, _assertionHashes);
        if (minL1AssertedBlock <= chainInfo.messagesConfirmedParentBlock) {
            revert NotAdvanced({
                currentBlock: chainInfo.messagesConfirmedParentBlock,
                messagesConfirmedParentBlock: minL1AssertedBlock,
                chainId: chainInfo.chainId
            });
        }

        chainInfo.messagesConfirmedParentBlock = minL1AssertedBlock;
        emit MessagesConfirmedBlockUpdated({
            blockNum: minL1AssertedBlock,
            chainId: chainInfo.chainId,
            isForceUpdate: false
        });
    }

    /// @notice Allows owner role (e.g., chain owner) to force an update. Can used if e.g., a known issue
    /// with confirmation on a governed chain is preventing proposals from being executed on the governance chain.
    /// @param _chainIndex The index in chains of the target chain.
    /// @param _parentBlockNumber New block number.
    function forceUpdateMessagesConfirmedParentBlock(
        uint256 _chainIndex,
        uint256 _parentBlockNumber
    ) external onlyOwner {
        ChainInfo storage chainInfo = chains[_chainIndex];
        chainInfo.messagesConfirmedParentBlock = _parentBlockNumber;
        emit MessagesConfirmedBlockUpdated({
            blockNum: _parentBlockNumber,
            chainId: chainInfo.chainId,
            isForceUpdate: true
        });
    }

    /// @notice returns true iff all messages are confirmed on all tracked child chains as of provided parent chain block
    /// @param _targetLlBlockNumber Parent chain block number to check against
    function allChildChainMessagesConfirmed(uint256 _targetLlBlockNumber)
        external
        view
        returns (bool)
    {
        for (uint256 i = 0; i < chains.length; i++) {
            if (_targetLlBlockNumber > chains[i].messagesConfirmedParentBlock) {
                return false;
            }
        }
        return true;
    }
}
