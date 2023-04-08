// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbitrumVestingWallet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ArbitrumVestingWalletsFactory is Ownable {
    event WalletCreated(address indexed beneficiary, address indexed vestingWalletAddress);

    /// @notice Create ArbitrumVestingWallets for each of the provided addresses
    /// @param _beneficiaries Addresses for whom to create vesting wallets
    /// @param _startTimestamp Time to start vesting for all created wallets
    /// @param _durationSeconds Duration over which to vest for all created wallets
    function createWallets(
        uint64 _startTimestamp,
        uint64 _durationSeconds,
        address[] memory _beneficiaries
    ) public onlyOwner returns (address[] memory) {
        address[] memory wallets = new address[](_beneficiaries.length);
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            ArbitrumVestingWallet wallet = new ArbitrumVestingWallet(
                _beneficiaries[i],
                _startTimestamp,
                _durationSeconds
            );
            wallets[i] = address(wallet);
            emit WalletCreated(_beneficiaries[i], address(wallet));
        }

        return wallets;
    }
}
