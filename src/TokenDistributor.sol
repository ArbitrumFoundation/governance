// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {uncheckedInc, IERC20VotesUpgradeable} from "./Util.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title  Token Distributor
/// @notice A contract responsible for distributing tokens.
/// @dev    After initialisation the following functions should be called in order
///         1. transfer tokens to this contract
///         2. setClaimPeriod - set the period during which users can claim
///         3. setRecipients - called as many times as required to set all the recipients
contract TokenDistributor is Initializable, OwnableUpgradeable {
    /// @notice Token to be distributed
    IERC20VotesUpgradeable public token;
    /// @notice address to receive tokens that were not claimed
    address payable public unclaimedTokensReciever;
    /// @notice amount of tokens that can be claimed by address
    mapping(address => uint256) public claimableTokens;
    /// @notice total amount of tokens claimable by recipients of this contract
    uint256 public totalClaimable;
    /// @notice block number at which claiming starts
    uint256 public claimPeriodStart;
    /// @notice block number at which claiming ends
    uint256 public claimPeriodEnd;

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

    constructor() {
        _disableInitializers();
    }

    /// @param _token token to be distributed (assumed to be an OZ implementation)
    /// @param _unclaimedTokensReciever address to receive leftover tokens after claiming period is over
    function initialize(IERC20VotesUpgradeable _token, address payable _unclaimedTokensReciever) external initializer {
        __Ownable_init();
        token = _token;
        unclaimedTokensReciever = _unclaimedTokensReciever;
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
        uint256 sum = 0;
        for (uint256 i = 0; i < _recipients.length; uncheckedInc(i)) {
            require(claimableTokens[_recipients[i]] == 0, "TokenDistributor: recipient already set");
            claimableTokens[_recipients[i]] = _claimableAmount[i];
            emit CanClaim(_recipients[i], _claimableAmount[i]);
            unchecked {
                sum += _claimableAmount[i];
            }
        }

        // we assign sum in this order to avoid an extra sload (optimiser doesn't seem to catch this)
        sum += totalClaimable;
        totalClaimable = sum;
        require(token.balanceOf(address(this)) >= sum, "TokenDistributor: not enough balance");
    }

    /// @notice allows admin to set the block range in which tokens can be claimed
    /// @dev uses block number for validation instead of block timestamp to keep consistent with the Governor
    function setClaimPeriod(uint256 start, uint256 end) external onlyOwner {
        require(start > block.number, "TokenDistributor: start should be in the future");
        require(end > start, "TokenDistributor: start should be before end");
        claimPeriodStart = start;
        claimPeriodEnd = end;
        emit ClaimPeriodUpdated(start, end);
    }

    /// @notice allows a token recipient to claim their tokens and delegate them in a single call
    /// @dev different implementations may handle validation/fail delegateBySig differently. here a OZ v4.6.0 impl is assumed
    /// @dev delegateBySig by OZ does not support `IERC1271`, so smart contract wallets should not use this method
    function claimAndDelegate(address delegatee, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
        claim();
        token.delegateBySig(delegatee, 0, expiry, v, r, s);
    }

    /// @notice sends leftover funds to unclaimed tokens reciever once the claiming period is over
    function sweep() external {
        require(claimPeriodEnd > 0, "TokenDistributor: claim period end not initialised");
        require(block.number >= claimPeriodEnd, "TokenDistributor: not ended");
        uint256 leftovers = token.balanceOf(address(this));
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
        require(block.number >= claimPeriodStart, "TokenDistributor: not started");
        require(block.number < claimPeriodEnd, "TokenDistributor: ended");

        uint256 amount = claimableTokens[msg.sender];
        require(amount > 0, "TokenDistributor: no value");

        claimableTokens[msg.sender] = 0;

        // we don't use safeTransfer since impl is assumed to be OZ
        require(token.transfer(msg.sender, amount), "TokenDistributor: fail token transfer");
        emit HasClaimed(msg.sender, amount);
    }
}
