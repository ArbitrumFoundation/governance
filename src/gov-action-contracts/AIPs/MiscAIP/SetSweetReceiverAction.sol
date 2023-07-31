// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../address-registries/L2AddressRegistry.sol";
import "../../../TokenDistributor.sol";

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
