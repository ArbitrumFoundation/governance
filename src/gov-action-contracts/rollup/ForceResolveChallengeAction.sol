// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";

contract ForceResolveChallengeAction {
    IRollupGetter public immutable addressRegistry;

    constructor(IRollupGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(address[] calldata stakerA, address[] calldata stakerB) external {
        IRollupAdmin(address(addressRegistry.rollup())).forceResolveChallenge(stakerA, stakerB);
    }
}
