// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

// CHRIS: TODO: we changed to 0.8 everywhere - do we want to do that?
import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

// CHRIS: TODO: why do we even has this contract?
contract ArbitrumTimelock is TimelockControllerUpgradeable {
    function initialize(uint256 minDelay, address[] memory proposers, address[] memory executors)
        external
        initializer
    {
        __TimelockController_init(minDelay, proposers, executors);
    }
}
