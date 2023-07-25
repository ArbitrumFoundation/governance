// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import '../src/gov-action-contracts/arb-precompiles/SetSpeedLimitAction.sol';
import "forge-std/Script.sol";

contract DeployScript is Script {
    function run() public {
        vm.startBroadcast();
        SetSpeedLimitAction action = new SetSpeedLimitAction();
        console.log(address(action));
        vm.stopBroadcast();
    }
}
