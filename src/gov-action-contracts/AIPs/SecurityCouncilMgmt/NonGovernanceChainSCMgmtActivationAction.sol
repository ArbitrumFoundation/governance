// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../../security-council-mgmt/interfaces/IGnosisSafe.sol";
import "./SecurityCouncilMgmtUpgradeLib.sol";

contract NonGovernanceChainSCMgmtActivationAction {
    IGnosisSafe public immutable newEmergencySecurityCouncil;
    IGnosisSafe public immutable prevEmergencySecurityCouncil;
    uint256 public immutable emergencySecurityCouncilThreshold;
    IUpgradeExecutor public immutable upgradeExecutor;

    constructor(
        IGnosisSafe _newEmergencySecurityCouncil,
        IGnosisSafe _prevEmergencySecurityCouncil,
        uint256 _emergencySecurityCouncilThreshold,
        IUpgradeExecutor _upgradeExecutor
    ) {
        newEmergencySecurityCouncil = _newEmergencySecurityCouncil;
        prevEmergencySecurityCouncil = _prevEmergencySecurityCouncil;
        emergencySecurityCouncilThreshold = _emergencySecurityCouncilThreshold;
        upgradeExecutor = _upgradeExecutor;
    }

    function perform() external {
        // swap in new emergency security council
        SecurityCouncilMgmtUpgradeLib.replaceEmergencySecurityCouncil({
            _prevSecurityCouncil: prevEmergencySecurityCouncil,
            _newSecurityCouncil: newEmergencySecurityCouncil,
            _threshold: emergencySecurityCouncilThreshold,
            _upgradeExecutor: upgradeExecutor
        });

        // confirm updates
        bytes32 EXECUTOR_ROLE = upgradeExecutor.EXECUTOR_ROLE();
        require(
            IAccessControlUpgradeable(address(upgradeExecutor)).hasRole(
                EXECUTOR_ROLE, address(newEmergencySecurityCouncil)
            ),
            "NonGovernanceChainSCMgmtActivationAction: new emergency security council not set"
        );
        require(
            !IAccessControlUpgradeable(address(upgradeExecutor)).hasRole(
                EXECUTOR_ROLE, address(prevEmergencySecurityCouncil)
            ),
            "NonGovernanceChainSCMgmtActivationAction: prev emergency security council still set"
        );
    }
}
