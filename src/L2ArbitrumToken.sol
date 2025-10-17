// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./TransferAndCallToken.sol";
import "@openzeppelin/contracts/utils/Checkpoints.sol";

/// @title  L2 Arbitrum Token
/// @notice The L2 counterparty of the Arbitrum token.
/// @dev    ERC20 with additional functionality:
///         * Permit - single step transfers via sig
///         * Votes - delegation and voting compatible with OZ governance
///         * Burnable - user's can burn their own tokens. Can be used by the airdrop distributor
///             after the claim period ends
///         * Mint - allows the owner to mint a maximum of 2% per year
///         * TransferAndCall - allows users to call a contract after doing a transfer
contract L2ArbitrumToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    OwnableUpgradeable,
    TransferAndCallToken
{
    using Checkpoints for Checkpoints.History;

    string private constant NAME = "Arbitrum";
    string private constant SYMBOL = "ARB";
    /// @notice The minimum amount of time that must elapse before a mint is allowed
    uint256 public constant MIN_MINT_INTERVAL = 365 days;
    /// @notice The maximum amount that can be can be minted - numerator
    uint256 public constant MINT_CAP_NUMERATOR = 200;
    /// @notice The maximum amount that can be can be minted - denominator
    uint256 public constant MINT_CAP_DENOMINATOR = 10_000;

    /// @notice The address of the L1 counterparty of this token
    address public l1Address;
    /// @notice The time at which the next mint is allowed - timestamp
    uint256 public nextMint;

    /// @dev History of the total amount of delegated tokens
    ///      The initial value is an estimate of the total delegation at the time of upgrade proposal creation.
    ///      Another proposal can be made later to update this value if needed.
    Checkpoints.History private _totalDelegationHistory;

    event TotalDelegationAdjusted(uint256 previousTotalDelegation, uint256 newTotalDelegation);

    constructor() {
        _disableInitializers();
    }

    /// @notice Initialise the L2 token
    /// @param _l1TokenAddress The address of the counterparty L1 token
    /// @param _initialSupply The amount of initial supply to mint
    /// @param _owner The owner of this contract - controls minting, not upgradeability
    function initialize(address _l1TokenAddress, uint256 _initialSupply, address _owner)
        public
        initializer
    {
        require(_l1TokenAddress != address(0), "ARB: ZERO_L1TOKEN_ADDRESS");
        require(_initialSupply != 0, "ARB: ZERO_INITIAL_SUPPLY");
        require(_owner != address(0), "ARB: ZERO_OWNER");

        __ERC20_init(NAME, SYMBOL);
        __ERC20Burnable_init();
        __ERC20Permit_init(NAME);
        __ERC20Votes_init();
        __Ownable_init();

        _mint(_owner, _initialSupply);
        nextMint = block.timestamp + MIN_MINT_INTERVAL;
        l1Address = _l1TokenAddress;
        _transferOwnership(_owner);
    }

    /// @notice Called after upgrade to set the initial total delegation estimate
    ///         The initial estimate may be manipulable with artificial delegation/undelegation prior to the upgrade.
    ///         Since this value is only used for quorum calculation, and the quroum is clamped by the governors to an acceptable range,
    ///         the risk/impact of manipulation is low.
    /// @param  initialTotalDelegation The initial total delegation at the time of upgrade proposal creation.
    ///         This is an estimate since it is chosen at proposal creation time and not effective until the proposal is executed.
    function postUpgradeInit(uint256 initialTotalDelegation) external onlyOwner {
        require(
            _totalDelegationHistory._checkpoints.length == 0,
            "ARB: POST_UPGRADE_INIT_ALREADY_CALLED"
        );
        _totalDelegationHistory.push(initialTotalDelegation);
    }

    /// @notice Adjusts total delegation value by the given amount
    /// @param  adjustment The amount that the total delegation is off by, negated. This is added to the current total delegation.
    function adjustTotalDelegation(int256 adjustment)
        external
        onlyOwner
    {
        uint256 latest = _totalDelegationHistory.latest();
        int256 newValue = int256(latest) + adjustment;

        // negative newValue should be impossible
        // since the adjustment should bring the value to true total delegation
        // which is at minimum zero
        require(newValue >= 0, "ARB: NEGATIVE_TOTAL_DELEGATION");
        _totalDelegationHistory.push(uint256(newValue));

        emit TotalDelegationAdjusted(latest, uint256(newValue));
    }

    /// @notice Allows the owner to mint new tokens
    /// @dev    Only allows minting below an inflation cap.
    ///         Set to once per year, and a maximum of 2%.
    function mint(address recipient, uint256 amount) external onlyOwner {
        // function inspired by: https://github.com/ensdomains/governance/blob/548f3f3607c83717427d9ae3fc1f3a9e66fc7642/contracts/ENSToken.sol#L105
        require(
            amount <= (totalSupply() * MINT_CAP_NUMERATOR) / MINT_CAP_DENOMINATOR,
            "ARB: MINT_TOO_MUCH"
        );
        require(block.timestamp >= nextMint, "ARB: MINT_TOO_EARLY");

        nextMint = block.timestamp + MIN_MINT_INTERVAL;
        _mint(recipient, amount);
    }

    /// @notice Get the current total delegation
    /// @return The current total delegation
    function getTotalDelegation() external view returns (uint256) {
        return _totalDelegationHistory.latest();
    }

    /// @notice Get the total delegation at a specific block number
    ///         If the blockNumber is prior to the first checkpoint, returns 0
    /// @param blockNumber The block number to get the total delegation at
    /// @return The total delegation at the given block number
    function getTotalDelegationAt(uint256 blockNumber) external view returns (uint256) {
        return _totalDelegationHistory.getAtBlock(blockNumber);
    }

    /// @dev Checks if total delegation needs to be updated, and updates it if so
    ///      by adding a new checkpoint.
    /// @param fromDelegate The address of the delegate the tokens are being moved from
    /// @param toDelegate The address of the delegate the tokens are being moved to
    /// @param amount The amount of tokens being moved
    function _updateDelegationHistory(address fromDelegate, address toDelegate, uint256 amount)
        internal
    {
        if (fromDelegate != toDelegate) {
            int256 delta = 0;
            if (fromDelegate != address(0)) {
                delta -= int256(amount);
            }
            if (toDelegate != address(0)) {
                delta += int256(amount);
            }
            if (delta != 0) {
                // if the initial estimate is too low, and a large amount of tokens are undelegated
                // it is technically possible that the newValue is negative
                // if this happens, we clamp it to zero to avoid underflow
                int256 newValue = int256(_totalDelegationHistory.latest()) + delta;
                _totalDelegationHistory.push(uint256(newValue < 0 ? int256(0) : newValue));
            }
        }
    }

    /// @dev Override ERC20VotesUpgradeable to update total delegation history when delegation changes
    function _delegate(address delegator, address delegatee) internal virtual override {
        _updateDelegationHistory(delegates(delegator), delegatee, balanceOf(delegator));
        super._delegate(delegator, delegatee);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._afterTokenTransfer(from, to, amount);
        _updateDelegationHistory(delegates(from), delegates(to), amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._burn(account, amount);
    }
}
