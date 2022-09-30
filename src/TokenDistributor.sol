// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {uncheckedInc, IERC20VotesUpgradeable} from "./Util.sol";

import "@openzeppelin/contracts-upgradeable-0.8/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable-0.8/proxy/utils/Initializable.sol";

/// @title  Token Distributor
/// @notice A contract responsible for distributing tokens
contract TokenDistributor is Initializable, OwnableUpgradeable {
    IERC20VotesUpgradeable public token;
    address payable public unclaimedTokensReciever;
    mapping(address => uint256) public claimableTokens;
    uint256 public totalClaimable;
    uint256 public claimPeriodStart;
    uint256 public claimPeriodEnd;

    event ClaimPeriodUpdated(uint256 start, uint256 end);
    event Claimed(address who, uint256 amount);
    event RecipientClaimableSet(address who, uint256 amount);
    event Swept(uint256 amount);

    constructor() {
        _disableInitializers();
    }

    /// @param _token token to be distributed (assumed to be an OZ implementation)
    function initialize(IERC20VotesUpgradeable _token, address payable _unclaimedTokensReciever) external initializer {
        token = _token;
        unclaimedTokensReciever = _unclaimedTokensReciever;
    }

    function depositToken(uint256 amount) external {
        require(token.transferFrom(msg.sender, address(this), amount), "TokenDistributor: fail transfer token");
    }

    function setRecipients(address[] calldata _recipients, uint256[] calldata _claimableAmount) external onlyOwner {
        require(_recipients.length == _claimableAmount.length, "TokenDistributor: invalid array length");
        uint256 sum = 0;
        for (uint256 i = 0; i < _recipients.length; uncheckedInc(i)) {
            require(claimableTokens[_recipients[i]] == 0, "TokenDistributor: recipient already set");
            claimableTokens[_recipients[i]] = _claimableAmount[i];
            unchecked {
                sum += _claimableAmount[i];
            }
        }

        sum += totalClaimable;
        totalClaimable = sum;
        require(token.balanceOf(address(this)) >= sum, "TokenDistributor: not enough balance");
    }

    function setClaimPeriod(uint256 start, uint256 end) external onlyOwner {
        require(start > block.timestamp, "TokenDistributor: start should be in the future");
        require(end > start, "TokenDistributor: start should be before end");
        claimPeriodStart = start;
        claimPeriodEnd = end;
        emit ClaimPeriodUpdated(start, end);
    }

    /// @dev different implementations may handle validation/fail delegateBySig differently. here a OZ v4.6.0 impl is assumed
    function claimAndDelegate(address delegatee, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external {
        claim();
        // TODO: can we pack into tighter calldata?
        token.delegateBySig(delegatee, 0, expiry, v, r, s);
    }

    function sweep() external {
        require(block.timestamp >= claimPeriodEnd, "TokenDistributor: not ended");
        uint256 leftovers = token.balanceOf(address(this));
        require(token.transfer(unclaimedTokensReciever, leftovers), "TokenDistributor: fail token transfer");

        emit Swept(leftovers);

        if (address(this).balance > 0) {
            // we transfer eth using an explicit call to make sure the receiver's fallback function is triggered
            (bool success,) = unclaimedTokensReciever.call{value: address(this).balance}("");
            require(success, "TokenDistributor: fail eth transfer");
        }
        // no funds should be sent because of previous step
        // contract is destroyed to clean up storage
        selfdestruct(payable(address(0)));
    }

    function claim() public {
        require(block.timestamp >= claimPeriodStart, "TokenDistributor: not started");
        require(block.timestamp < claimPeriodEnd, "TokenDistributor: ended");

        uint256 amount = claimableTokens[msg.sender];
        require(amount > 0, "TokenDistributor: no value");

        claimableTokens[msg.sender] = 0;

        // we don't use safeTransfer since impl is assumed to be OZ
        require(token.transfer(msg.sender, amount), "TokenDistributor: fail token transfer");
        emit Claimed(msg.sender, amount);
    }
}
