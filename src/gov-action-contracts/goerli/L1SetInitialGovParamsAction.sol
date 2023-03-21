// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "../address-registries/L1AddressRegistry.sol";

contract L1SetInitialGovParamsAction {
    uint256 public constant l1TimelockPeriod = 900; // seconds
    IL1AddressRegistry immutable registry;

    constructor(IL1AddressRegistry _registry) {
        registry = _registry;
    }

    function perform() external {
        IL1Timelock timelock = registry.l1Timelock();
        timelock.updateDelay(l1TimelockPeriod);
        require(
            timelock.getMinDelay() == l1TimelockPeriod,
            "L1SetInitialGovParamsAction: Timelock delay"
        );
    }
}
