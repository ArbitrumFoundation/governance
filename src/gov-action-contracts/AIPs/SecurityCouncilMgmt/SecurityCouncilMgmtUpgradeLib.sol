// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../../security-council-mgmt/interfaces/IGnosisSafe.sol";
import "@offchainlabs/upgrade-executor/src/IUpgradeExecutor.sol";
import "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";

library SecurityCouncilMgmtUpgradeLib {
    function replaceEmergencySecurityCouncil(
        IGnosisSafe _prevSecurityCouncil,
        IGnosisSafe _newSecurityCouncil,
        uint256 _threshold,
        IUpgradeExecutor _upgradeExecutor
    ) internal {
        requireSafesEquivalent(_prevSecurityCouncil, _newSecurityCouncil, _threshold);
        bytes32 EXECUTOR_ROLE = _upgradeExecutor.EXECUTOR_ROLE();
        require(
            IAccessControlUpgradeable(address(_upgradeExecutor)).hasRole(
                EXECUTOR_ROLE, address(_prevSecurityCouncil)
            ),
            "SecurityCouncilMgmtUpgradeLib: prev council not executor"
        );
        require(
            !IAccessControlUpgradeable(address(_upgradeExecutor)).hasRole(
                EXECUTOR_ROLE, address(_newSecurityCouncil)
            ),
            "SecurityCouncilMgmtUpgradeLib: new council already executor"
        );

        IAccessControlUpgradeable(address(_upgradeExecutor)).revokeRole(
            EXECUTOR_ROLE, address(_prevSecurityCouncil)
        );
        IAccessControlUpgradeable(address(_upgradeExecutor)).grantRole(
            EXECUTOR_ROLE, address(_newSecurityCouncil)
        );
    }

    function requireSafesEquivalent(
        IGnosisSafe _safe1,
        IGnosisSafe safe2,
        uint256 _expectedThreshold
    ) internal view {
        uint256 newSecurityCouncilThreshold = safe2.getThreshold();
        require(
            _safe1.getThreshold() == newSecurityCouncilThreshold,
            "SecurityCouncilMgmtUpgradeLib: threshold mismatch"
        );
        require(
            newSecurityCouncilThreshold == _expectedThreshold,
            "SecurityCouncilMgmtUpgradeLib: unexpected threshold"
        );

        address[] memory prevOwners = _safe1.getOwners();
        address[] memory newOwners = safe2.getOwners();
        require(
            areUniqueAddressArraysEqual(prevOwners, newOwners),
            "SecurityCouncilMgmtUpgradeLib: owners mismatch"
        );
    }

    /// @notice assumes each address array has no repeated elements (i.e., as is the enforced for gnosis safe owners)
    function areUniqueAddressArraysEqual(address[] memory array1, address[] memory array2)
        public
        pure
        returns (bool)
    {
        if (array1.length != array2.length) {
            return false;
        }

        for (uint256 i = 0; i < array1.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < array2.length; j++) {
                if (array1[i] == array2[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }

        return true;
    }
}
