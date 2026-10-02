// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {GlamsterdamForkGateAction} from "src/gov-action-contracts/glamsterdam/ForkGateAction.sol";
import {
    SetGlamsterdamGasParamsAction
} from "src/gov-action-contracts/glamsterdam/SetGlamsterdamGasParamsAction.sol";

/// @notice Deploys the Glamsterdam action contracts on the current chain: the fork gate on
///         Ethereum, the gas params action on Arbitrum One and Nova.
///         Uses CREATE2 for deterministic addresses and easy verification.
contract DeployGlamsterdamActions is Script {
    function run() external {
        vm.startBroadcast();

        bytes32 salt = bytes32(uint256(1));

        if (block.chainid == 1) {
            GlamsterdamForkGateAction gate = new GlamsterdamForkGateAction{salt: salt}();
            console.log("GlamsterdamForkGateAction deployed at:", address(gate));
            console.log("probe deployed at:", gate.probe());
        } else if (block.chainid == 42_161 || block.chainid == 42_170) {
            SetGlamsterdamGasParamsAction action = new SetGlamsterdamGasParamsAction{salt: salt}();
            console.log("SetGlamsterdamGasParamsAction deployed at:", address(action));
        } else {
            revert("DeployGlamsterdamActions: unsupported chain");
        }

        vm.stopBroadcast();
    }
}
