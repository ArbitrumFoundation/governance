// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./L2ArbitrumGovernor.sol";
import "./L2ArbitrumToken.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title  Givernance treasury excrow
/// @dev delegates its votes the exclude address
contract ArbTreasury is Initializable {
    address public arbToken;
    address public treasuryGov;

    constructor() {
        _disableInitializers();
    }

    /// @notice Arbitrum governance treasury. Exludes its votes from quorum count by delegating exclude address upon creation.
    function initialize(address payable _treasuryGovAddress) public initializer {
        require(_treasuryGovAddress != address(0), "NULL_TREASURYGOV");
        L2ArbitrumGovernor _treasuryGov = L2ArbitrumGovernor(_treasuryGovAddress);
        IVotesUpgradeable _arbToken = IVotesUpgradeable(_treasuryGov.token());
        _arbToken.delegate(_treasuryGov.EXCLUDE_ADDRESS());

        arbToken = address(_arbToken);
        treasuryGov = _treasuryGovAddress;
    }

    modifier onlyFromTreasuryGov() {
        require(msg.sender == treasuryGov, "NOT_FROM_TREASURYGOV");
        _;
    }

    /// @notice treasuryGov can transfer arbitrary token from escrow
    function transferToken(address token, address to, uint256 amount)
        public
        onlyFromTreasuryGov
        returns (bool)
    {
        bool success = IERC20(token).transfer(to, amount);
        require(success, "TRANSFER_FAILED");
        return success;
    }

    /// @notice treasuryGov can transfer Arb-Token from escrow (convenience method)
    function transferArbToken(address to, uint256 amount) public returns (bool) {
        return transferToken(arbToken, to, amount);
    }

    /// @notice treasuryGov can transfer ETH from escrow
    function sendETH(address payable _to) public payable onlyFromTreasuryGov {
        (bool sent,) = _to.call{value: msg.value}("");
        require(sent, "SEND_FAULED");
    }
}
