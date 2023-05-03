// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./interfaces/ISecurityCouncilUpgradeExectutor.sol";
import "./interfaces/IGnosisSafe.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract SecurityCouncilUpgradeExecutor is
    ISecurityCouncilUpgradeExectutor,
    Initializable,
    OwnableUpgradeable
{
    address internal constant SENTINEL_OWNERS = address(0x1);

    IGnosisSafe public securityCouncil;

    constructor() {
        _disableInitializers();
    }

    function initialize(IGnosisSafe _securityCouncil, address _owner) public initializer {
        securityCouncil = _securityCouncil;
        _transferOwnership(_owner);
    }

    function updateMembers(address[] memory _membersToAdd, address[] memory _membersToRemove)
        external
        onlyOwner
    {
        // TODO: depluplicate? 
        uint256 threshold = securityCouncil.getThreshold();
        for (uint256 i = 0; i < _membersToRemove.length; i++) {
            address member = _membersToRemove[i];
            for (uint256 i = 0; i < _membersToAdd.length; i++) {
                // TODO: owner check?
                _addMember(_membersToAdd[i], threshold);
            }

            // skip, don't revert, if it's not a member
            if (securityCouncil.isOwner(member)) {
                _removeMember(member, threshold);
            }
        }
        // TODO: sanity check for threshold ?
    }

    function _addMember(address _member, uint256 _threshold) internal {
        _execFromModule(
            abi.encodeWithSelector(IGnosisSafe.addOwnerWithThreshold.selector, _member, _threshold)
        );
    }

    function _removeMember(address _member, uint256 _threshold) internal {
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

    function _execFromModule(bytes memory data) internal {
        securityCouncil.execTransactionFromModule(
            address(securityCouncil), 0, data, Enum.Operation.Call
        );
    }
}
