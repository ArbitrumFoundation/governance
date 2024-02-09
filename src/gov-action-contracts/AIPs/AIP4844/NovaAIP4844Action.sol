// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./AIP4844Action.sol";

/// @notice Upgrade Nova core contracts in preparation for 4844
contract NovaAIP4844Action is AIP4844Action {
    constructor()
        AIP4844Action(
            L1AddressRegistry(0x2F06643fc2CC18585Ae790b546388F0DE4Ec6635), // L1 address registry for Nova,
            bytes32(""), // wasm module root  TODO
            address(0), // new sequencer inbox impl TODO
            address(0), // new challenge manager imp TODO
            ProxyAdmin(0x5613AF0474EB9c528A34701A5b1662E3C8FA0678), // l1 gov proxy admin
            address(0) // new one step proof  TODO
        )
    {}
}
