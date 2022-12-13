// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {IERC20VotesUpgradeable} from "./Util.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title  Token Distributor
/// @notice Holds tokens for users to claim.
/// @dev    Unlike a merkle distributor this contract uses storage to record claims rather than a
///         merkle root. This is because calldata on Arbitrum is relatively expensive when compared with
///         storage, since calldata uses L1 gas.
///         After construction do the following
///         1. transfer tokens to this contract
///         2. setRecipients - called as many times as required to set all the recipients
///         3. transferOwnership - the ownership of the contract should be transferred to a new owner (eg DAO) after all recipients have been set
contract TokenDistributor is Ownable {
    /// @notice Token to be distributed
    IERC20VotesUpgradeable public immutable token;
    /// @notice Address to receive tokens that were not claimed
    address payable public sweepReceiver;
    /// @notice amount of tokens that can be claimed by address
    mapping(address => uint256) public claimableTokens;
    /// @notice Total amount of tokens claimable by recipients of this contract
    uint256 public totalClaimable;
    /// @notice Block number at which claiming starts
    uint256 public immutable claimPeriodStart;
    /// @notice Block number at which claiming ends
    uint256 public immutable claimPeriodEnd;

    /// @notice recipient can claim this amount of tokens
    event CanClaim(address indexed recipient, uint256 amount);
    /// @notice recipient has claimed this amount of tokens
    event HasClaimed(address indexed recipient, uint256 amount);
    /// @notice leftover tokens after claiming period have been swept
    event Swept(uint256 amount);
    /// @notice new address set to receive unclaimed tokens
    event SweepReceiverSet(address indexed newSweepReceiver);
    /// @notice Tokens withdrawn
    event Withdrawal(address indexed recipient, uint256 amount);

    constructor(
        IERC20VotesUpgradeable _token,
        address payable _sweepReceiver,
        address _owner,
        uint256 _claimPeriodStart,
        uint256 _claimPeriodEnd,
        address delegateTo
    ) Ownable() {
        require(address(_token) != address(0), "TokenDistributor: zero token address");
        require(_sweepReceiver != address(0), "TokenDistributor: zero sweep address");
        require(_owner != address(0), "TokenDistributor: zero owner address");
        require(_claimPeriodStart > block.number, "TokenDistributor: start should be in the future");
        require(_claimPeriodEnd > _claimPeriodStart, "TokenDistributor: start should be before end");
        require(delegateTo != address(0), "TokenDistributor: zero delegate to");

        _token.delegate(delegateTo);
        token = _token;
        _setSweepReciever(_sweepReceiver);
        claimPeriodStart = _claimPeriodStart;
        claimPeriodEnd = _claimPeriodEnd;
        _transferOwnership(_owner);
    }

    /// @notice Allows owner to update address of sweep receiver
    function setSweepReciever(address payable _sweepReceiver) external onlyOwner {
        _setSweepReciever(_sweepReceiver);
    }

    function _setSweepReciever(address payable _sweepReceiver) internal {
        require(_sweepReceiver != address(0), "TokenDistributor: zero sweep receiver address");
        sweepReceiver = _sweepReceiver;
        emit SweepReceiverSet(_sweepReceiver);
    }

    /// @notice Allows owner of the contract to withdraw tokens
    /// @dev A safety measure in case something goes wrong with the distribution
    function withdraw(uint256 amount) external onlyOwner {
        require(token.transfer(msg.sender, amount), "TokenDistributor: fail transfer token");
        emit Withdrawal(msg.sender, amount);
    }

    /// @notice Allows owner to set a list of recipients to receive tokens
    /// @dev This may need to be called many times to set the full list of recipients
    function setRecipients(address[] calldata _recipients, uint256[] calldata _claimableAmount)
        external
        onlyOwner
    {
        require(
            _recipients.length == _claimableAmount.length, "TokenDistributor: invalid array length"
        );
        uint256 sum = totalClaimable;
        for (uint256 i = 0; i < _recipients.length; i++) {
            // sanity check that the address being set is consistent
            require(claimableTokens[_recipients[i]] == 0, "TokenDistributor: recipient already set");
            claimableTokens[_recipients[i]] = _claimableAmount[i];
            emit CanClaim(_recipients[i], _claimableAmount[i]);
            unchecked {
                sum += _claimableAmount[i];
            }
        }

        // sanity check that the current has been sufficiently allocated
        require(token.balanceOf(address(this)) >= sum, "TokenDistributor: not enough balance");
        totalClaimable = sum;
    }

    /// @notice Claim and delegate in a single call
    /// @dev Different implementations may handle validation/fail delegateBySig differently. here a OZ v4.6.0 impl is assumed
    /// @dev delegateBySig by OZ does not support `IERC1271`, so smart contract wallets should not use this method
    /// @dev delegateBySig is used so that the token contract doesn't need to contain any claiming functionality
    function claimAndDelegate(address delegatee, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        external
    {
        claim();
        // WARNING: there's a nuisance attack that can occur here on networks that allow front running
        // A malicious party could see the signature when it's broadcast to a public mempool and create a
        // new transaction to front run by calling delegateBySig on the token with the sig. The result would
        // be that the tx to claimAndDelegate would fail. This is only a nuisance as the user can just call the
        // claim function below to claim their funds, however it would be an annoying UX and they would have paid
        // for a failed transaction. If using this function on a network that allows front running consider
        // modifying it to put the delegateBySig in a try/catch and rethrow for all errors that aren't "nonce invalid"
        token.delegateBySig(delegatee, 0, expiry, v, r, s);
        // ensure that delegation did take place, this is just a sanity check that ensures the signature
        // matched to the sender who was claiming. It helps to detect errors in forming signatures
        require(token.delegates(msg.sender) == delegatee, "TokenDistributor: delegate failed");
    }

    /// @notice Sends any unclaimed funds to the sweep reciever once the claiming period is over
    function sweep() external {
        require(block.number >= claimPeriodEnd, "TokenDistributor: not ended");
        uint256 leftovers = token.balanceOf(address(this));
        require(leftovers != 0, "TokenDistributor: no leftovers");

        require(token.transfer(sweepReceiver, leftovers), "TokenDistributor: fail token transfer");

        emit Swept(leftovers);

        // contract is destroyed to clean up storage
        selfdestruct(payable(sweepReceiver));
    }

    /// @notice Allows a recipient to claim their tokens
    /// @dev Can only be called during the claim period
    function claim() public {
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
