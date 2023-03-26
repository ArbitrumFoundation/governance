// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbitrumVestingWalletManager.sol";

contract ArbitrumVestingWalletsFactory {
    event WalletManagerCreated(address indexed beneficiary, address indexed vestingWalletAddress);

    /// @notice Create ArbitrumVestingWalletManager for each of the provided addresses
    /// @param _startTimestamp Time to start vesting for all created wallets
    /// @param _durationSeconds Duration over which to vest for all created wallets
    /// @param _beneficiaries Addresses for whom to create vesting wallets
    function createWallets(
        uint64 _startTimestamp,
        uint64 _durationSeconds,
        address[] memory _beneficiaries
    ) public returns (address[] memory) {
        address[] memory wallets = new address[](_beneficiaries.length);
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            ArbitrumVestingWalletManager wallet = new ArbitrumVestingWalletManager(
                _beneficiaries[i],
                _startTimestamp,
                _durationSeconds
            );
            wallets[i] = address(wallet);
            emit WalletManagerCreated(_beneficiaries[i], address(wallet));
        }

        return wallets;
    }
}
