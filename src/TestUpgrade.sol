// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// CHRIS: TODO: remove this to the tests folder

// CHRIS: TODO: would be nice to really tighten these things up
// CHRIS: TODO: eg. we could have a template and inherit from that
// CHRIS: TODO: then we always call into that
// CHRIS: TODO: one thing about that is that we cant do random calls - what about the signature?

contract TestUpgrade {
    function upgrade(IERC20 token, address to, uint256 amount) public {
        require(token.transfer(to, amount), "UPGRADE1: Failed transfer");
    }
}

// CHRIS: TODO: should we have the

// CHRIS: TODO: testing upgrades is gonna be a nightmare? we could set up a rig to just inject the data into?
// CHRIS: TODO: using hardhat forking

// CHRIS: TODO: hand in the governor this week - and other stuff a week after
