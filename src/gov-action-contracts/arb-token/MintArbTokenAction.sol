// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";

contract MintArbTokenAction {
    IL2ArbitrumTokenGetter public immutable govAddressRegisry;

    constructor(IL2ArbitrumTokenGetter _govAddressRegisry) {
        govAddressRegisry = _govAddressRegisry;
    }

    function perform(address recipient, uint256 amount) external {
        govAddressRegisry.l2ArbitrumToken().mint(recipient, amount);
    }
}
