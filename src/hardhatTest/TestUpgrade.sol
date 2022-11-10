// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// CHRIS: TODO: remove TestUpgrade from the src - it should only be in /test/
// CHRIS: TODO: remove this to the tests folder
// CHRIS: TODO: document the risks and checks that need to be done on an upgrade contract
// CHRIS: TODO: testing upgrades is gonna be a nightmare? we could set up a rig to just inject the data into?
// CHRIS: TODO: using hardhat forking?
// CHRIS: TODO: write a bunch of stuff about how the UpgradeExecutor should be used

contract TestUpgrade {
    function upgrade(IERC20 token, address to, uint256 amount) public {
        require(token.transfer(to, amount), "UPGRADE1: Failed transfer");
    }
}
