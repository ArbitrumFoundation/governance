// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IWETH9 {
    function deposit() external payable;

    function withdraw(uint256 _amount) external;
}

/// @notice Contract that be used as an Orbit chain's governance token.
/// Functions as an ERC20 wrapper for the chain's native asset and and implements the IVotesUpgradeable interface.
/// Also includes parent chain token address for Gateway compatibility.
contract WrappedNativeGovToken is
    IWETH9,
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable
{
    constructor() {
        _disableInitializers();
    }

    /// @notice The address of the parent chain counterpart of this token
    address public l1Address;

    /// @param _name Token name
    /// @param _symbol Token symbol
    /// @param _parentChainTokenAddress Address of the parent chain counterpart of this token
    /// @param _initialSupply Initial token supply
    /// @param _initialSupplyRecipient Recipient of initial token supply
    function initialize(
        string memory _name,
        string memory _symbol,
        address _parentChainTokenAddress,
        uint256 _initialSupply,
        address _initialSupplyRecipient
    ) external initializer {
        l1Address = _parentChainTokenAddress;
        _mint(_initialSupplyRecipient, _initialSupply);
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __ERC20Votes_init();
    }

    function deposit() external payable override {
        depositTo(msg.sender);
    }

    function withdraw(uint256 amount) external override {
        withdrawTo(msg.sender, amount);
    }

    function depositTo(address account) public payable {
        _mint(account, msg.value);
    }

    function withdrawTo(address account, uint256 amount) public {
        _burn(msg.sender, amount);
        (bool success,) = account.call{value: amount}("");
        require(success, "FAIL_TRANSFER");
    }

    receive() external payable {
        depositTo(msg.sender);
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
