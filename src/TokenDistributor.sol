// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {uncheckedInc, IERC20VotesUpgradeable} from "./Util.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title  Token Distributor
/// @notice A contract responsible for distributing tokens.
/// @dev    After initialisation the following functions should be called in order
///         1. transfer tokens to this contract
///         2. setClaimPeriod - set the period during which users can claim
///         3. setRecipients - called as many times as required to set all the recipients
contract TokenDistributor is Ownable {
    /// @notice Token to be distributed
    IERC20VotesUpgradeable public immutable token;
    /// @notice address to receive tokens that were not claimed
    address payable public unclaimedTokensReciever;
    /// @notice amount of tokens that can be claimed by address
    mapping(address => uint256) public claimableTokens;
    /// @notice total amount of tokens claimable by recipients of this contract
    uint256 public totalClaimable;
    /// @notice block number at which claiming starts
    uint256 public immutable claimPeriodStart;
    /// @notice block number at which claiming ends
    uint256 public immutable claimPeriodEnd;

    /// @notice range of blocks in which claiming may happen
    event ClaimPeriodUpdated(uint256 start, uint256 end);
    /// @notice recipient can claim this amount of tokens
    event CanClaim(address recipient, uint256 amount);
    /// @notice recipient has claimed this amount of tokens
    event HasClaimed(address recipient, uint256 amount);
    /// @notice leftover tokens after claiming period have been swept
    event Swept(uint256 amount);
    /// @notice new address set to receive unclaimed tokens
    event UnclaimedTokensRecieverSet(address newUnclaimedTokensReciever);

    constructor(
        IERC20VotesUpgradeable _token,
        address payable _unclaimedTokensReciever,
        address _owner,
        uint256 _claimPeriodStart,
        uint256 _claimPeriodEnd
    ) Ownable() {
        // CHRIS: TODO: we should standardise error messages - use custom errors?
        require(address(_token) != address(0), "TokenDistributor: ZERO_TOKEN");
        require(_unclaimedTokensReciever != address(0), "TokenDistributor: ZERO_UNCLAIMED_RECEIVER");
        require(_owner != address(0), "TokenDistributor: ZERO_OWNER");
        require(_claimPeriodStart > block.number, "TokenDistributor: start should be in the future");
        require(_claimPeriodEnd > _claimPeriodStart, "TokenDistributor: start should be before end");

        token = _token;
        unclaimedTokensReciever = _unclaimedTokensReciever;
        claimPeriodStart = _claimPeriodStart;
        claimPeriodEnd = _claimPeriodEnd;
        _transferOwnership(_owner);

        // CHRIS: TODO: is this necessary? we can see it from the args...
        emit UnclaimedTokensRecieverSet(_unclaimedTokensReciever);
    }

    /// @notice allows owner to update address of unclaimed tokens receiver
    function setUnclaimedTokensReciever(address payable _unclaimedTokensReciever) external onlyOwner {
        unclaimedTokensReciever = _unclaimedTokensReciever;
        emit UnclaimedTokensRecieverSet(_unclaimedTokensReciever);
    }

    /// @notice allows owner of the contract to withdraw tokens when paused
    function withdraw(uint256 amount) external onlyOwner {
        require(token.transfer(msg.sender, amount), "TokenDistributor: fail transfer token");
    }

    /// @notice allows owner to set list of recipients to receive tokens
    function setRecipients(address[] calldata _recipients, uint256[] calldata _claimableAmount) external onlyOwner {
        require(_recipients.length == _claimableAmount.length, "TokenDistributor: invalid array length");
        uint256 sum = totalClaimable;
        for (uint256 i = 0; i < _recipients.length; i++) {
            require(claimableTokens[_recipients[i]] == 0, "TokenDistributor: recipient already set");
            claimableTokens[_recipients[i]] = _claimableAmount[i];
            emit CanClaim(_recipients[i], _claimableAmount[i]);
            unchecked {
                sum += _claimableAmount[i];
            }
        }

        require(token.balanceOf(address(this)) >= sum, "TokenDistributor: not enough balance");
        totalClaimable = sum;
    }

    // CHRIS: TODO: the docs in this file really need updating

    /// @notice allows a token recipient to claim their tokens and delegate them in a single call
    /// @dev different implementations may handle validation/fail delegateBySig differently. here a OZ v4.6.0 impl is assumed
    /// @dev delegateBySig by OZ does not support `IERC1271`, so smart contract wallets should not use this method
    function claimAndDelegate(address delegatee, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
        claim();
        token.delegateBySig(delegatee, 0, expiry, v, r, s);

        // CHRIS: TODO: write a comment on why it's not necessary to worry about front running

        // try token.delegateBySig(delegatee, 0, expiry, v, r, s) {}
        // catch Error(string memory reason) {
        //     if (keccak256(abi.encodePacked(reason)) != keccak256(abi.encodePacked("ERC20Votes: invalid nonce"))) {
        //         revert(reason);
        //     }
        // }

        // // ensure that delegation did take place
        // // CHRIS: TODO: docs on why we need to do this
        require(token.delegates(msg.sender) == delegatee, "TokenDistributor: delegate failed");

        // CHRIS: TODO: maybe just do known risks
        // CHRIS: TODO: should we check that the claimer is also the signer?
        // CHRIS: TODO: there's a potential DOS here where someone is annoying be making delegate claims on behalf of someone else
        // CHRIS: TODO: result is their claimAndDelegate will fail? and they'll have to do normal delegation
        // CHRIS: TODO: could get round this by doing a try/catch on the actual delegation but this would be dangerous because we may fuck up the actual delegation
        // CHRIS: TODO: better to do front end where we can actually check if the user has delegated?
        // CHRIS: TODO: we want to stop people stealing the sig.. we could further wrap it up? nope, they can always unwrap
        // CHRIS: TODO: basically nothing we can do about this since the nonce will already have been used
    }

    /// @notice sends leftover funds to unclaimed tokens reciever once the claiming period is over
    function sweep() external {
        require(block.number >= claimPeriodEnd, "TokenDistributor: not ended");
        uint256 leftovers = token.balanceOf(address(this));
        require(leftovers != 0, "TokenDistributor: no leftovers");
        require(token.transfer(unclaimedTokensReciever, leftovers), "TokenDistributor: fail token transfer");

        emit Swept(leftovers);

        if (address(this).balance > 0) {
            // this address shouldn't hold any eth. but if it does, we transfer eth using an
            // explicit call to make sure the receiver's fallback function is triggered
            (bool success,) = unclaimedTokensReciever.call{value: address(this).balance}("");

            // if this fails, we continue regardless and funds will be transfered through self destruct
        }
        // no funds should be sent because of previous step (unless the contract doesnt have a payable fallback func)
        // contract is destroyed to clean up storage
        selfdestruct(payable(unclaimedTokensReciever));
    }

    /// @notice allows a recipient to claim their tokens
    function claim() public {
        // CHRIS: TODO: could these error messages be better?
        require(block.number >= claimPeriodStart, "TokenDistributor: claim not started");
        require(block.number < claimPeriodEnd, "TokenDistributor: claim ended");

        uint256 amount = claimableTokens[msg.sender];
        require(amount > 0, "TokenDistributor: nothing to claim");

        claimableTokens[msg.sender] = 0;

        // we don't use safeTransfer since impl is assumed to be OZ
        require(token.transfer(msg.sender, amount), "TokenDistributor: fail token transfer");
        emit HasClaimed(msg.sender, amount);
    }
}
