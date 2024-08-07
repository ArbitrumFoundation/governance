// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistryInterfaces.sol";
 
/// @notice Updates the delay of the core gov timelock to 8 days
contract CoreGovTimelockUpdateDelayEightDayAction {
    ICoreGovTimelockGetter public immutable govAddressRegistry;
    uint256 public constant delay = 86400 * 8;

    constructor(ICoreGovTimelockGetter _govAddressRegistry) {
        govAddressRegistry = _govAddressRegistry;
    }

    function perform() external {
        govAddressRegistry.coreGovTimelock().updateDelay(delay);
        require(
            govAddressRegistry.coreGovTimelock().getMinDelay() == delay,
            "CoreGovTimelockUpdateDelayAction: Timelock delay"
        );
    }
}
