// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./L2ArbitrumVestingWallet.sol";

contract L2ArbitrumVestingWalletsFactory {
    uint64 public immutable startTimestamp;
    uint64 public immutable durationSeconds;
    address public immutable distributor;
    address public immutable token;
    address payable immutable governer;

    event WalletCreated(
        address indexed beneficiary,
        address indexed vestingWalletAddress
    );

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

    function createWallets(address[] memory wallets) public {
        for (uint256 i = 0; i < wallets.length; i++) {
            L2ArbitrumVestingWallet wallet = new L2ArbitrumVestingWallet(
                wallets[i],
                startTimestamp,
                durationSeconds,
                distributor,
                token,
                governer
            );
            emit WalletCreated(wallets[i], address(wallet));
        }
    }
}
