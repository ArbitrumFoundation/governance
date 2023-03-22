// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/precompiles/ArbOwner.sol";

library ArbPrecompilesLib {
    ArbOwner constant arbOwner = ArbOwner(0x0000000000000000000000000000000000000070);
}
