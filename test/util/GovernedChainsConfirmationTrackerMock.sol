// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "../../src/interfaces/IGovernedChainsConfirmationTracker.sol";

contract GovernedChainsConfirmationTrackerMock is IGovernedChainsConfirmationTracker {
    function allChildChainMessagesConfirmed(uint256 _targetLlBlockNumber)
        external
        view
        returns (bool)
    {
        return true;
    }
}
