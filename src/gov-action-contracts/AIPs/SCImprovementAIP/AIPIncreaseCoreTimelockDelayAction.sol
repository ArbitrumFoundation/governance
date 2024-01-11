// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../governance/UpdateCoreTimelockDelayAction.sol";
import "../../address-registries/L2AddressRegistry.sol";

///@notice Increase core timelock day to eight days.
/// For discussion / rationale, see https://forum.arbitrum.foundation/t/rfc-constitutional-aip-security-council-improvement-proposal/20541
contract AIPIncreaseCoreTimelockDelayAction is UpdateCoreTimelockDelayAction {
    constructor()
        UpdateCoreTimelockDelayAction(
            ICoreGovTimelockGetter(0x56C4E9Eb6c63aCDD19AeC2b1a00e4f0d7aBda9d3),
            8 days
        )
    {}
}
