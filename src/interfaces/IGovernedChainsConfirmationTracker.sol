// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IGovernedChainsConfirmationTracker {
    function allChildChainMessagesConfirmed(uint256 _targetLlBlockNumber)
        external
        view
        returns (bool);
}
