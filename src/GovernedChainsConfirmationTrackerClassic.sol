// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IGovernedChainsConfirmationTracker.sol";
import "@arbitrum/nitro-contracts/src/rollup/IRollupCore.sol";

/// @notice classic (i.e., non-bold) version
contract GovernedChainsConfirmationTrackerClassic is IGovernedChainsConfirmationTracker {
    ChainInfo[] public chains;

    error NotAContract(address addr);

    /// @notice Data stored for each tracked chain
    struct ChainInfo {
        uint256 chainId; // child chain's chain id (for convenience / readability)
        address rollupAddress; // address of child-chain's core Rollup contract
    }

    constructor(ChainInfo[] memory _chains) {
        for (uint256 i = 0; i < _chains.length; i++) {
            if (!Address.isContract(_chains[i].rollupAddress)) {
                revert NotAContract(_chains[i].rollupAddress);
            }
            chains.push(_chains[i]);
        }
    }
    /// @notice returns true iff all messages are confirmed on all tracked child chains as of provided parent chain block
    /// @param _targetLlBlockNumber Parent chain block number to check against

    function allChildChainMessagesConfirmed(uint256 _targetLlBlockNumber)
        external
        view
        returns (bool)
    {
        for (uint256 i = 0; i < chains.length; i++) {
            IRollupCore rollup = IRollupCore(chains[i].rollupAddress);

            Node memory secondLatestConfirmedNode = rollup.getNode(rollup.latestConfirmed() - 1);

            if (secondLatestConfirmedNode.createdAtBlock <= _targetLlBlockNumber) {
                return false;
            }
        }
        return true;
    }
}
