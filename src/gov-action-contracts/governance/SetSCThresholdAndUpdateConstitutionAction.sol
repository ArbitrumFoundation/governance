// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../security-council-mgmt/interfaces/IGnosisSafe.sol";
import "../../interfaces/IArbitrumDAOConstitution.sol";
import "./ConstitutionActionLib.sol";

interface _IGnosisSafe {
    function changeThreshold(uint256 _threshold) external;
}

///@notice Set the minimum signing threshold for a security council gnosis safe. Assumes that the safe has the UpgradeExecutor added as a module.
/// Also conditionally updates constitution dependent on its current hash.
contract SetSCThresholdAndUpdateConstitutionAction {
    IGnosisSafe public immutable gnosisSafe;
    uint256 public immutable oldThreshold;
    uint256 public immutable newThreshold;
    IArbitrumDAOConstitution public immutable constitution;
    bytes32 public immutable oldConstitutionHash;
    bytes32 public immutable newConstitutionHash;

    event ActionPerformed(uint256 newThreshold, bytes32 newConstitutionHash);

    constructor(
        IGnosisSafe _gnosisSafe,
        uint256 _oldThreshold,
        uint256 _newThreshold,
        IArbitrumDAOConstitution _constitution,
        bytes32 _oldConstitutionHash,
        bytes32 _newConstitutionHash
    ) {
        gnosisSafe = _gnosisSafe;
        oldThreshold = _oldThreshold;
        newThreshold = _newThreshold;
        constitution = _constitution;
        oldConstitutionHash = _oldConstitutionHash;
        newConstitutionHash = _newConstitutionHash;
    }

    function perform() external {
        require(
            constitution.constitutionHash() == oldConstitutionHash, "WRONG_OLD_CONSTITUTION_HASH"
        );
        constitution.setConstitutionHash(newConstitutionHash);
        require(constitution.constitutionHash() == newConstitutionHash, "NEW_CONSTITUTION_HASH_SET");
        // sanity check old threshold
        require(
            gnosisSafe.getThreshold() == oldThreshold, "SecSCThresholdAction: WRONG_OLD_THRESHOLD"
        );

        gnosisSafe.execTransactionFromModule({
            to: address(gnosisSafe),
            value: 0,
            data: abi.encodeWithSelector(_IGnosisSafe.changeThreshold.selector, newThreshold),
            operation: OpEnum.Operation.Call
        });
        // sanity check new threshold was set
        require(
            gnosisSafe.getThreshold() == newThreshold, "SecSCThresholdAction: NEW_THRESHOLD_NOT_SET"
        );
        emit ActionPerformed(newThreshold, constitution.constitutionHash());
    }
}
