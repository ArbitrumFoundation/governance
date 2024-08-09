// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistryInterfaces.sol";
 
/// @notice Updates the delay of the core gov timelock to 8 days
contract CoreGovTimelockUpdateDelayEightDayAction {
    ICoreGovTimelockGetter public constant govAddressRegistry = ICoreGovTimelockGetter(0x56C4E9Eb6c63aCDD19AeC2b1a00e4f0d7aBda9d3);
    uint256 public constant delay = 86400 * 8;

    function perform() external {
        govAddressRegistry.coreGovTimelock().updateDelay(delay);
        require(
            govAddressRegistry.coreGovTimelock().getMinDelay() == delay,
            "CoreGovTimelockUpdateDelayAction: Timelock delay"
        );
    }
}
