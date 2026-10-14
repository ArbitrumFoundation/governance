// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {L2StateMirror} from "./L2StateMirror.sol";
import {DelegateMapping} from "./DelegateMapping.sol";

/// @notice Everything the L1ArbitrumGovernor reads from its "voting token". VotingTokenMirror
///         implements this so it can stand in for the ARB token as the governor's source of
///         voting power.
interface IVotingTokenMirror {
    /// @notice Voting power of an L1 account (resolved to its L2 delegate) as of a block number
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);
    /// @notice Voting power of an L2 account as of a block number, without delegate resolution
    function getPastVotesByL2(address l2Account, uint256 blockNumber)
        external
        view
        returns (uint256);
    /// @notice Total delegated voting power as of a block number
    function getTotalDelegationAt(uint256 blockNumber) external view returns (uint256);
}

/// @notice Stands in for the ARB token as the L1 governor's source of voting power, backed by L2
///         state proven against confirmed assertions.
/// @dev    An L1 account votes with an L2 delegate's power iff the delegate claimed that L1
///         account in the L2 DelegateMapping as of the proposal snapshot's assertion, and the L1
///         account claims the delegate in the L1 DelegateMapping.
contract VotingTokenMirror is IVotingTokenMirror {
    /// @notice Serves proven L2 state
    L2StateMirror public immutable stateMirror;
    /// @notice Maps L1 voting addresses to their claimed L2 delegates
    DelegateMapping public immutable l1DelegateMapping;

    error NotClaimed(address l1Account);
    error ClaimMismatch(address l1Account, address l2Delegate, address claimedL1Address);

    constructor(address _stateMirror, address _l1DelegateMapping) {
        stateMirror = L2StateMirror(_stateMirror);
        l1DelegateMapping = DelegateMapping(_l1DelegateMapping);
    }

    /// @notice Voting power proven for an L1 account as of an L1 block
    /// @dev    Resolves the L1 account to its claimed L2 delegate, then requires the delegate's
    ///         claim proven at that block's assertion to name the L1 account. Reverts if the
    ///         account claims no delegate, the delegate's claim is unproven or names a different
    ///         L1 account, or the delegate's votes are unproven.
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256) {
        address l2Delegate = l1DelegateMapping.claimed(account);
        if (l2Delegate == address(0)) {
            revert NotClaimed(account);
        }
        address claimedL1 = stateMirror.getL1AddressAt(l2Delegate, blockNumber);
        if (claimedL1 != account) {
            revert ClaimMismatch(account, l2Delegate, claimedL1);
        }
        return stateMirror.getVotesAt(l2Delegate, blockNumber);
    }

    /// @notice Voting power proven for an L2 account as of an L1 block, without delegate resolution
    function getPastVotesByL2(address l2Account, uint256 blockNumber)
        external
        view
        returns (uint256)
    {
        return stateMirror.getVotesAt(l2Account, blockNumber);
    }

    /// @notice Total delegation of the L2 ARB token proven as of an L1 block
    function getTotalDelegationAt(uint256 blockNumber) external view returns (uint256) {
        return stateMirror.getTotalDelegationAt(blockNumber);
    }
}
