// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./AIP4844Action.sol";

/// @notice Upgrade ArbOne core contracts in preparation for 4844
contract ArbOneAIP4844Action is AIP4844Action {
    constructor()
        AIP4844Action(
            L1AddressRegistry(0xd514C2b3aaBDBfa10800B9C96dc1eB25427520A0), // L1 address registry for Arb One,
            bytes32(""), // wasm module root  TODO
            address(0), // new sequencer inbox impl TODO
            address(0), // new challenge manager imp TODO
            ProxyAdmin(0x5613AF0474EB9c528A34701A5b1662E3C8FA0678), // l1 gov proxy admin
            address(0) // new one step proof  TODO
        )
    {}
}
