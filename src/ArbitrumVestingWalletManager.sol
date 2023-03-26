// SP// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbitrumVestingWallet.sol";
import {IERC20VotesUpgradeable} from "./Util.sol";

/// @notice Tokens sent this contract can be sent into any number of ArbitrumVotingWallet as the beneifciary chooses
/// This lets the beneficiary partition their delegated votes to a number of different addresses.
contract ArbitrumVestingWalletManager {
    address public immutable beneficiary;
    uint64 public immutable start;
    uint64 public immutable duration;
    address[] public vestingWallets;

    event VestingWalletCreated(address indexed walletAddress, uint256 indexed walletIndex);
    event VestingWalletFunded(
        address indexed walletAddress,
        uint256 indexed walletIndex,
        address indexed token,
        uint256 amount
    );

    constructor(address _beneficiary, uint64 _startTimestamp, uint64 _durationSeconds) {
        beneficiary = _beneficiary;
        start = _startTimestamp;
        duration = _durationSeconds;
        // create with one vesting wallet:
        _createVestingWallet();
    }

    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary, "ArbitrumVestingWalletManager: not beneficiary");
        _;
    }

    function createVestingWallet() external onlyBeneficiary returns (uint256 walletIndex) {
        _createVestingWallet();
    }

    function fundVestingWallet(address token, uint256 amount, uint256 walletIndex)
        external
        onlyBeneficiary
    {
        _fundVestingWallet(token, amount, walletIndex);
    }

    function createAndFundVestingWallet(address token, uint256 amount)
        external
        onlyBeneficiary
        returns (uint256 newWalletIndex)
    {
        uint256 newWalletIndex = _createVestingWallet();
        _fundVestingWallet(token, amount, newWalletIndex);
    }

    function _createVestingWallet() private returns (uint256 newWalletIndex) {
        ArbitrumVestingWallet arbitrumVestingWallet =
            new ArbitrumVestingWallet(beneficiary, start, duration);
        vestingWallets.push(address(arbitrumVestingWallet));
        uint256 newWalletIndex = vestingWalletsLength() - 1;
        emit VestingWalletCreated(address(arbitrumVestingWallet), newWalletIndex);
    }

    function _fundVestingWallet(address token, uint256 amount, uint256 walletIndex) private {
        address vestingWalletAddress = vestingWalletAt(walletIndex);
        require(
            IERC20VotesUpgradeable(token).transfer(vestingWalletAddress, amount),
            "ArbitrumVestingWalletManager: transfer failed"
        );
        emit VestingWalletFunded(vestingWalletAddress, walletIndex, token, amount);
    }

    function vestingWalletsLength() public view returns (uint256) {
        return vestingWallets.length;
    }

    function vestingWalletAt(uint256 index) public view returns (address) {
        require(index < vestingWalletsLength(), "ArbitrumVestingWalletManager: index out of bounds");
        return vestingWallets[index];
    }
}
