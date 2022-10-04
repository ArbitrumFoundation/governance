// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

abstract contract xChainTest {
    fallback() external payable {
        revert("not implemented");
    }
}
