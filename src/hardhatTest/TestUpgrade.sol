// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestUpgrade {
    function upgrade(IERC20 token, address to, uint256 amount) public {
        require(token.transfer(to, amount), "UPGRADE1: Failed transfer");
    }
}
