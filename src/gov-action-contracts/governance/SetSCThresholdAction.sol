// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IGnosisSafe {
    function getThreshold() external view returns (uint256);
    function changeThreshold(uint256 _threshold) external;
}

///@notice Set the minimum signing threshold for a security council gnosis safe. Assumes that the safe has the UpgradeExecutor added as a module.
contract SetSCThresholdAction {
    IGnosisSafe public immutable gnosisSafe;
    uint256 public immutable oldThreshold;
    uint256 public immutable newThreshold;

    constructor(IGnosisSafe _gnosisSafe, uint256 _oldThreshold, uint256 _newThreshold) {
        gnosisSafe = _gnosisSafe;
        oldThreshold = _oldThreshold;
        newThreshold = _newThreshold;
    }

    function perform() external {
        // sanity check old threshold
        require(
            gnosisSafe.getThreshold() == oldThreshold, "SecSCThresholdAction: WRONG_OLD_THRESHOLD"
        );

        gnosisSafe.changeThreshold(newThreshold);
        // sanity check new threshold was set
        require(
            gnosisSafe.getThreshold() == newThreshold, "SecSCThresholdAction: NEW_THRESHOLD_NOT_SET"
        );
    }
}
