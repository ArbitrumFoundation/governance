// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./UpgradeAndEnableFastConfirmAction.sol";
import "../../address-registries/L1AddressRegistry.sol";

contract NovaUpgradeAndEnableFastConfirmAction is UpgradeAndEnableFastConfirmAction {
    constructor()
        UpgradeAndEnableFastConfirmAction(
            L1AddressRegistry(0x2F06643fc2CC18585Ae790b546388F0DE4Ec6635),
            0x2f9491DB1920726d0cFE8AC5F1caC1f730C5dC44, // v2.1.0 RollupAdminLogic
            0x5c93BAB9Ff2Fa3884b643bd8545C625De0633517, // v2.1.0 RollupUserLogic
            0x0000000000000000000000000000000000000000, // TODO: anyTrustFastConfirmer
            1 // TODO: newMinimumAssertionPeriod in blocks
        )
    {}
}
