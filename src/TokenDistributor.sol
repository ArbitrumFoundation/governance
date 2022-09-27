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
    uint256 public claimPeriodStart;
    uint256 public claimPeriodEnd;

    event ClaimPeriodUpdated(uint256 start, uint256 end);
    event Claimed(address who, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    /// @param _token token to be distributed (assumed to be an OZ implementation)
    function initialize(IERC20VotesUpgradeable _token, address payable _unclaimedTokensReciever) external initializer {
        token = _token;
        unclaimedTokensReciever = _unclaimedTokensReciever;
    }

    function setRecipients(address[] calldata _recipients, uint256[] calldata _claimableAmount) external onlyOwner {
        require(_recipients.length == _claimableAmount.length, "invalid");
        for (uint256 i = 0; i < _recipients.length; uncheckedInc(i)) {
            // this intentionally does not emit events to save on gas
            claimableTokens[_recipients[i]] = _claimableAmount[i];
        }
        // TODO: should we check if the contract has enough tokens escrowed to cover the claimable amounts?
    }

    function setClaimPeriod(uint256 start, uint256 end) external onlyOwner {
        require(start > block.timestamp, "invalid");
        require(start > end, "invalid");
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
        require(block.timestamp >= claimPeriodEnd, "not ended");
        uint256 leftovers = token.balanceOf(address(this));
        require(token.transfer(unclaimedTokensReciever, leftovers), "fail transfer");

        if (address(this).balance > 0) {
            (bool success,) = unclaimedTokensReciever.call{value: address(this).balance}("");
            require(success, "FAIL_TRANSFER");
        }

        // no funds should be sent because of previous step
        // contract is destroyed to clean up storage
        selfdestruct(payable(address(0)));
    }

    function claim() public {
        require(block.timestamp >= claimPeriodStart, "not started");
        require(block.timestamp < claimPeriodEnd, "ended");

        uint256 amount = claimableTokens[msg.sender];
        require(amount > 0, "no value");

        claimableTokens[msg.sender] = 0;

        // we don't use safeTransfer since impl is assumed to be OZ
        require(token.transfer(msg.sender, amount), "fail transfer");
        emit Claimed(msg.sender, amount);
    }
}
