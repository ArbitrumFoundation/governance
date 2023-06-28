// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./interfaces/IGnosisSafe.sol";
import "./SecurityCouncilMgmtUtils.sol";

/// @notice Action contract for updating security council members. Used by the security council management system.
contract SecurityCouncilUpgradeAction {
    address internal constant SENTINEL_OWNERS = address(0x1);

    IGnosisSafe public immutable securityCouncil;

    constructor(address _securityCouncil) {
        securityCouncil = IGnosisSafe(_securityCouncil);
    }

    /// @notice updates members of security council multisig to match provided array
    function updateMembers(address[] memory _updatedMembers) external {
        // always preserve current threshold
        uint256 threshold = securityCouncil.getThreshold();

        address[] memory membersToAdd = new address[](6);
        uint8 membersToAddCount = 0;

        for (uint256 i = 0; i < _updatedMembers.length; i++) {
            address member = _updatedMembers[i];
            if (!securityCouncil.isOwner(member)) {
                membersToAdd[membersToAddCount] = member;
                membersToAddCount++;
            }
        }

        address[] memory membersToRemove = new address[](6);
        uint8 membersToRemoveCount = 0;

        address[] memory owners = securityCouncil.getOwners();
        for (uint256 i = 0; i < owners.length; i++) {
            address owner = owners[i];
            if (!SecurityCouncilMgmtUtils.isInArray(owner, _updatedMembers)) {
                membersToRemove[membersToRemoveCount] = owner;
                membersToRemoveCount++;
            }
        }

        for (uint256 i = 0; i < membersToAddCount; i++) {
            _addMember(membersToAdd[i], threshold);
        }
        for (uint256 i = 0; i < membersToRemoveCount; i++) {
            _removeMember(membersToRemove[i], threshold);
        }
    }

    function _addMember(address _member, uint256 _threshold) internal {
        _execFromModule(
            abi.encodeWithSelector(IGnosisSafe.addOwnerWithThreshold.selector, _member, _threshold)
        );
    }

    function _removeMember(address _member, uint256 _threshold) internal {
        // owners are stored as a linked list and removal requires the previous owner
        address[] memory owners = securityCouncil.getOwners();
        address previousOwner = SENTINEL_OWNERS;
        for (uint256 i = 0; i < owners.length; i++) {
            address currentOwner = owners[i];
            if (currentOwner == _member) {
                break;
            }
            previousOwner = currentOwner;
        }
        _execFromModule(
            abi.encodeWithSelector(
                IGnosisSafe.removeOwner.selector, previousOwner, _member, _threshold
            )
        );
    }

    /// @notice execute provided operation via gnosis safe's trusted  execTransactionFromModule entry point
    function _execFromModule(bytes memory data) internal {
        securityCouncil.execTransactionFromModule(
            address(securityCouncil), 0, data, OpEnum.Operation.Call
        );
    }
}
