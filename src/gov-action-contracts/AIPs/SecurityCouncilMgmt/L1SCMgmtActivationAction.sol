// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../../security-council-mgmt/interfaces/IGnosisSafe.sol";
import "@offchainlabs/upgrade-executor/src/IUpgradeExecutor.sol";
import "../../../interfaces/ICoreTimelock.sol";
import "./SecurityCouncilMgmtUpgradeLib.sol";

contract L1SCMgmtActivationAction {
    IGnosisSafe public immutable newEmergencySecurityCouncil;
    IGnosisSafe public immutable prevEmergencySecurityCouncil;
    uint256 public immutable emergencySecurityCouncilThreshold;
    IUpgradeExecutor public immutable l1UpgradeExecutor;
    ICoreTimelock public immutable l1Timelock;

    constructor(
        IGnosisSafe _newEmergencySecurityCouncil,
        IGnosisSafe _prevEmergencySecurityCouncil,
        uint256 _emergencySecurityCouncilThreshold,
        IUpgradeExecutor _l1UpgradeExecutor,
        ICoreTimelock _l1Timelock
    ) {
        newEmergencySecurityCouncil = _newEmergencySecurityCouncil;
        prevEmergencySecurityCouncil = _prevEmergencySecurityCouncil;
        emergencySecurityCouncilThreshold = _emergencySecurityCouncilThreshold;
        l1UpgradeExecutor = _l1UpgradeExecutor;
        l1Timelock = _l1Timelock;
    }

    function perform() external {
        // swap in new emergency security council
        SecurityCouncilMgmtUpgradeLib.replaceEmergencySecurityCouncil({
            _prevSecurityCouncil: prevEmergencySecurityCouncil,
            _newSecurityCouncil: newEmergencySecurityCouncil,
            _threshold: emergencySecurityCouncilThreshold,
            _upgradeExecutor: l1UpgradeExecutor
        });

        // swap in new emergency security council canceller role
        bytes32 TIMELOCK_CANCELLER_ROLE = l1Timelock.CANCELLER_ROLE();
        require(
            l1Timelock.hasRole(TIMELOCK_CANCELLER_ROLE, address(prevEmergencySecurityCouncil)),
            "GovernanceChainSCMgmtActivationAction: prev emergency security council should have cancellor role"
        );
        require(
            !l1Timelock.hasRole(TIMELOCK_CANCELLER_ROLE, address(l1UpgradeExecutor)),
            "GovernanceChainSCMgmtActivationAction: l1UpgradeExecutor already has cancellor role"
        );

        l1Timelock.revokeRole(TIMELOCK_CANCELLER_ROLE, address(prevEmergencySecurityCouncil));
        l1Timelock.grantRole(TIMELOCK_CANCELLER_ROLE, address(l1UpgradeExecutor));

        // confirm updates
        require(
            l1Timelock.hasRole(TIMELOCK_CANCELLER_ROLE, address(l1UpgradeExecutor)),
            "GovernanceChainSCMgmtActivationAction: l1UpgradeExecutor canceller role not set"
        );
        require(
            !l1Timelock.hasRole(TIMELOCK_CANCELLER_ROLE, address(prevEmergencySecurityCouncil)),
            "GovernanceChainSCMgmtActivationAction: prevEmergencySecurityCouncil canceller role not revoked"
        );
    }
}
