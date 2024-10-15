// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {BaseDeployer} from "script/BaseDeployer.sol";
import {L2ArbitrumGovernorV2} from "src/L2ArbitrumGovernorV2.sol";

// Deploy script for the underlying implementation that will be used by both Governor proxies
contract DeployImplementation is BaseDeployer {
  function run() public returns (L2ArbitrumGovernorV2 _implementation) {
    vm.startBroadcast(deployerPrivateKey);
    _implementation = new L2ArbitrumGovernorV2();
    vm.stopBroadcast();
  }
}
