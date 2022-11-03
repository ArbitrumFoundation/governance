// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./VotingVestingWallet.sol";

contract VestingWalletsFactory {
    uint64 public immutable startTimestamp;
    uint64 public immutable durationSeconds;
    address public immutable distributor;
    address public immutable token;
    address payable immutable governer;

    event WalletCreated(address indexed beneficiary, address indexed vestingWalletAddress);

    /**
     * @param _startTimestamp  time to start vesting for all created wallets
     * @param _durationSeconds during over while to vest for all created wallets
     * @param _distributor token distribution contract
     * @param _token ARB token (to vest)
     * @param _governer Arbitrum L2 governer contract
     */
    constructor(
        uint64 _startTimestamp,
        uint64 _durationSeconds,
        address _distributor,
        address _token,
        address payable _governer
    ) {
        startTimestamp = _startTimestamp;
        durationSeconds = _durationSeconds;
        distributor = _distributor;
        token = _token;
        governer = _governer;
    }

    /**
     * @notice Create L2ArbitrumVestingWallets for each of the provided addresses
     * @param _beneficiaries addresses at which to creat walelts
     */
    function createWallets(address[] memory _beneficiaries) public {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            VotingVestingWallet wallet = new VotingVestingWallet(
                _beneficiaries[i],
                startTimestamp,
                durationSeconds,
                distributor,
                token,
                governer
            );
            emit WalletCreated(_beneficiaries[i], address(wallet));
        }
    }
}
