// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistryInterfaces.sol";
 
/// @notice Updates the delay of the core gov timelock
contract CoreGovTimelockUpdateDelayAction {
    ICoreGovTimelockGetter public immutable govAddressRegistry;
    uint256 public immutable delay = 86400 * 1; // TODO: change 1 to the result of the snapshot

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
