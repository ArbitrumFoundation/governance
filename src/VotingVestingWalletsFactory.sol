// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./VotingVestingWallet.sol";

contract VestingWalletsFactory {
    event WalletCreated(address indexed beneficiary, address indexed vestingWalletAddress);

    /**
     * @notice Create L2ArbitrumVestingWallets for each of the provided addresses
     * @param _beneficiaries Addresses for whom to create vesting wallets
     * @param _startTimestamp Time to start vesting for all created wallets
     * @param _durationSeconds Duration over which to vest for all created wallets
     */
    function createWallets(uint64 _startTimestamp, uint64 _durationSeconds, address[] memory _beneficiaries) public {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            VotingVestingWallet wallet = new VotingVestingWallet(
                _beneficiaries[i],
                _startTimestamp,
                _durationSeconds
            );
            emit WalletCreated(_beneficiaries[i], address(wallet));
        }
    }
}
