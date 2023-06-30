// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./interfaces/IGnosisSafe.sol";
import "./SecurityCouncilMgmtUtils.sol";

/// @notice Action contract for updating security council members. Used by the security council management system.
contract SecurityCouncilUpgradeAction {
    address internal constant SENTINEL_OWNERS = address(0x1);

    /// @notice updates members of security council multisig to match provided array
    function perform(address _securityCouncil, address[] memory _updatedMembers) external {
        IGnosisSafe securityCouncil = IGnosisSafe(_securityCouncil);
        // always preserve current threshold
        uint256 threshold = securityCouncil.getThreshold();

        address[] memory previousOwners = securityCouncil.getOwners();

        for (uint256 i = 0; i < _updatedMembers.length; i++) {
            address member = _updatedMembers[i];
            if (!securityCouncil.isOwner(member)) {
                _addMember(securityCouncil, member, threshold);
            }
        }

        for (uint256 i = 0; i < previousOwners.length; i++) {
            address owner = previousOwners[i];
            if (!SecurityCouncilMgmtUtils.isInArray(owner, _updatedMembers)) {
                _removeMember(securityCouncil, owner, threshold);
            }
        }
    }

    function _addMember(IGnosisSafe securityCouncil, address _member, uint256 _threshold)
        internal
    {
        _execFromModule(
            securityCouncil,
            abi.encodeWithSelector(IGnosisSafe.addOwnerWithThreshold.selector, _member, _threshold)
        );
    }

    function _removeMember(IGnosisSafe securityCouncil, address _member, uint256 _threshold)
        internal
    {
        // owners are stored as a linked list and removal requires the previous owner
        address[] memory owners = securityCouncil.getOwners();
        address previousOwner = _getPrevOwner(_member, owners);
        _execFromModule(
            securityCouncil,
            abi.encodeWithSelector(
                IGnosisSafe.removeOwner.selector, previousOwner, _member, _threshold
            )
        );
    }

    function _getPrevOwner(address _owner, address[] memory _owners)
        internal
        view
        returns (address previousOwner)
    {
        address previousOwner = SENTINEL_OWNERS;
        for (uint256 i = 0; i < _owners.length; i++) {
            address currentOwner = _owners[i];
            if (currentOwner == _owner) {
                break;
            }
            previousOwner = currentOwner;
        }
    }

    /// @notice execute provided operation via gnosis safe's trusted  execTransactionFromModule entry point
    function _execFromModule(IGnosisSafe securityCouncil, bytes memory data) internal {
        securityCouncil.execTransactionFromModule(
            address(securityCouncil), 0, data, OpEnum.Operation.Call
        );
    }
}
