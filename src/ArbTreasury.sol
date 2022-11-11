// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./L2ArbitrumGovernor.sol";
import "./L2ArbitrumToken.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title  Governance treasury excrow
/// @dev delegates its votes the exclude address
contract ArbTreasury is Initializable {
    address public arbToken;
    address public treasuryGov;

    event EthSent(address indexed recipient, uint256 amount);
    event TokensSent(address indexed token, address indexed recipient, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    /// @notice Arbitrum governance treasury. Exludes its votes from quorum count by delegating exclude address upon creation.
    function initialize(address payable _treasuryGovAddress) public initializer {
        require(_treasuryGovAddress != address(0), "ArbTreasury: zero treasury gov address");
        L2ArbitrumGovernor _treasuryGov = L2ArbitrumGovernor(_treasuryGovAddress);
        IVotesUpgradeable _arbToken = IVotesUpgradeable(_treasuryGov.token());
        _arbToken.delegate(_treasuryGov.EXCLUDE_ADDRESS());

        arbToken = address(_arbToken);
        treasuryGov = _treasuryGovAddress;
    }

    modifier onlyFromTreasuryGov() {
        require(msg.sender == treasuryGov, "ArbTreasury: not from treasury gov");
        _;
    }

    /// @notice treasuryGov can transfer arbitrary token from escrow
    function transferToken(address _token, address _to, uint256 _amount)
        public
        onlyFromTreasuryGov
        returns (bool)
    {
        bool success = IERC20(_token).transfer(_to, _amount);
        require(success, "ArbTreasury: transfer failed");
        emit TokensSent(_token, _to, _amount);
        return success;
    }

    /// @notice treasuryGov can transfer Arb-Token from escrow (convenience method)
    function transferArbToken(address _to, uint256 _amount) public returns (bool) {
        return transferToken(arbToken, _to, _amount);
    }

    /// @notice treasuryGov can transfer ETH from escrow
    function sendETH(address payable _to, uint256 _amount)
        public
        payable
        onlyFromTreasuryGov
        returns (bool)
    {
        (bool sent,) = _to.call{value: _amount}("");
        require(sent, "ArbTreasury: Send failed");
        emit EthSent(_to, _amount);
        return sent;
    }
}
