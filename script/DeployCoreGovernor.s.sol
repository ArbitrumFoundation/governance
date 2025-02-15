// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {BaseGovernorDeployer, L2ArbitrumGovernorV2} from "script/BaseGovernorDeployer.sol";

// Concrete deployment script for the Arbitrum L2 Core Governor.
contract DeployCoreGovernor is BaseGovernorDeployer {
  function NAME() public pure override returns (string memory) {
    return "Core L2ArbitrumGovernor";
  }

  function TIMELOCK_ADDRESS() public pure override returns (address payable) {
    return payable(L2_CORE_GOVERNOR_TIMELOCK);
  }

  function QUORUM_NUMERATOR() public pure override returns (uint256) {
    return 500;
  }

  function run(address _implementation) public override returns (L2ArbitrumGovernorV2 _governor) {
    return super.run(_implementation);
  }
}
