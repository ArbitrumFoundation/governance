// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./TransferAndCallToken.sol";

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

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._afterTokenTransfer(from, to, amount);
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
