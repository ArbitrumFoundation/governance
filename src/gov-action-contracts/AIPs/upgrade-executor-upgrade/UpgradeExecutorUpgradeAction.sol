// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {UpgradeExecutor} from "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
import {ERC1967Upgrade} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

contract UpgradeExecutorUpgradeAction is ERC1967Upgrade {
    address public immutable newUpgradeExecutorImplementation = address(new UpgradeExecutor());

    function perform() external {
        _upgradeTo(newUpgradeExecutorImplementation);
        require(
            _getImplementation() == newUpgradeExecutorImplementation,
            "UpgradeExecutorUpgradeAction: upgrade failed"
        );
    }
}
