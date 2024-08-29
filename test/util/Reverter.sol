// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

contract Reverter {
    fallback() external payable {
        revert("REVERTER_FAIL");
    }
}
