// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @notice Lets an account claim an account on the other chain. Deployed to both chains: on L2,
///         delegates claim the L1 address that votes with their power; on L1, voting addresses
///         claim their L2 delegate.
/// @dev    The L2 side mapping should be deployed and populated well before the L1 side of the
///         system is live. This prevents a situation where a malicious proposal is created on
///         L1 which forces delegates to scramble to update their claims.
contract DelegateMapping {
    /// @notice Account to the account it claims on the other chain
    mapping(address => address) public claimed;

    /// @notice Emitted when an account claims an account on the other chain
    event Claimed(address indexed account, address indexed claimedAccount);

    /// @notice Claim an account on the other chain. Claim the zero address to revoke; on L2 a
    ///         zeroed slot is unprovable on L1, so no one can vote with the delegate's power via
    ///         L2StateMirror.proveL1Address. Revoking does not invalidate a signature the delegate
    ///         already produced for L2StateMirror.claimL1AddressBySig.
    function claim(address account) external {
        claimed[msg.sender] = account;
        emit Claimed(msg.sender, account);
    }
}
