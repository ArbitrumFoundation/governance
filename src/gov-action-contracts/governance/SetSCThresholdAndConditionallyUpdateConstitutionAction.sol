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
contract SetSCThresholdAndConditionallyUpdateConstitutionAction {
    IGnosisSafe public immutable gnosisSafe;
    uint256 public immutable oldThreshold;
    uint256 public immutable newThreshold;
    IArbitrumDAOConstitution public immutable constitution;
    bytes32 public immutable oldConstitutionHash1;
    bytes32 public immutable newConstitutionHash1;
    bytes32 public immutable oldConstitutionHash2;
    bytes32 public immutable newConstitutionHash2;

    event ActionPerformed(uint256 newThreshold, bytes32 newConstitutionHash);

    constructor(
        IGnosisSafe _gnosisSafe,
        uint256 _oldThreshold,
        uint256 _newThreshold,
        IArbitrumDAOConstitution _constitution,
        bytes32 _oldConstitutionHash1,
        bytes32 _newConstitutionHash1,
        bytes32 _oldConstitutionHash2,
        bytes32 _newConstitutionHash2
    ) {
        gnosisSafe = _gnosisSafe;
        oldThreshold = _oldThreshold;
        newThreshold = _newThreshold;
        constitution = _constitution;
        oldConstitutionHash1 = _oldConstitutionHash1;
        newConstitutionHash1 = _newConstitutionHash1;
        oldConstitutionHash2 = _oldConstitutionHash2;
        newConstitutionHash2 = _newConstitutionHash2;
    }

    function perform() external {
        bytes32[] memory oldConstitutionHashes = new bytes32[](2);
        oldConstitutionHashes[0] = oldConstitutionHash1;
        oldConstitutionHashes[1] = oldConstitutionHash2;

        bytes32[] memory newConstitutionHashes = new bytes32[](2);
        newConstitutionHashes[0] = newConstitutionHash1;
        newConstitutionHashes[1] = newConstitutionHash2;

        ConstitutionActionLib.conditonallyUpdateConstitutionHash({
            _constitution: constitution,
            _oldConstitutionHashes: oldConstitutionHashes,
            _newConstitutionHashes: newConstitutionHashes
        });

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
