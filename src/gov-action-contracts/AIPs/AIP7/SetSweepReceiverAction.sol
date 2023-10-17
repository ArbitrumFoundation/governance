// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../address-registries/L2AddressRegistry.sol";
import "../../../TokenDistributor.sol";

/// @notice Change sweep receiver address (address to which unclaimed tokens after the airdrop are sent) from L2 Core Timelock to DAO Treasury
/// Tokens in both contracts are controlled by the DAO, but DAO Treasury is preferred here for 2 reasons:
/// 1) It is delegated to the exclude address
/// 2) It already holds the rest of the DAO control tokens
contract SetSweepReceiverAction {
    IL2AddressRegistry public immutable l2GovAddressRegistry;
    TokenDistributor public immutable tokenDistributor;

    constructor(IL2AddressRegistry _l2GovAddressRegistry, TokenDistributor _tokenDistributor) {
        l2GovAddressRegistry = _l2GovAddressRegistry;
        tokenDistributor = _tokenDistributor;
    }

    function perform() external {
        address treasuryWallet = address(l2GovAddressRegistry.treasuryWallet());

        tokenDistributor.setSweepReciever(payable(treasuryWallet));

        // verify:
        require(
            tokenDistributor.sweepReceiver() == treasuryWallet,
            "SetSweepReceiverAction: new sweep receiver set"
        );
    }
}
