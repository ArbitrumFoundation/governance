// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title An ERC20 wallet with fixed delegation
/// @notice Only supports the transfer functionality of a wallet
///         Only allows delegation for one token
contract FixedDelegateErc20Wallet is OwnableUpgradeable {
    constructor() {
        _disableInitializers();
    }

    /// @notice         Initialise the wallet. Sets the delegate for this wallet
    ///                 which then cannot be changed for the lifetime of this wallet
    /// @param token    The token for which delegation is fixed
    /// @param delegateTo Who to delegate this wallet's votes to
    /// @param owner    The owner of this wallet
    function initialize(address token, address delegateTo, address owner) public initializer {
        require(token != address(0), "FixedDelegateErc20Wallet: zero token address");
        require(delegateTo != address(0), "FixedDelegateErc20Wallet: zero delegateTo address");
        require(owner != address(0), "FixedDelegateErc20Wallet: zero owner address");

        __Ownable_init();

        IVotesUpgradeable voteToken = IVotesUpgradeable(token);
        voteToken.delegate(delegateTo);

        _transferOwnership(owner);
    }

    /// @notice Transfer tokens from this wallet
    function transfer(address _token, address _to, uint256 _amount)
        public
        onlyOwner
        returns (bool)
    {
        bool success = IERC20(_token).transfer(_to, _amount);
        require(success, "FixedDelegateErc20Wallet: transfer failed");
        return success;
    }
}
