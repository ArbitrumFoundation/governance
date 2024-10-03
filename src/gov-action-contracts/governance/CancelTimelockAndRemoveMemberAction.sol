// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";
import "./CancelTimelockOperation.sol";

contract CancelTimelockAndRemoveMemberOAction {
    IL2AddressRegistry public immutable l2AddressRegistry;

    constructor(IL2AddressRegistry _l2AddressRegistry) {
        l2AddressRegistry = _l2AddressRegistry;
    }

    // CHRIS: TODO: restrict this to ony being able to cancel rotation props and not any prop
    function perform(address memberToRemove, bytes32 operationId) public {
        // first remove the council member
        ISecurityCouncilManager scm = l2AddressRegistry.securityCouncilManager();
        IAccessControlUpgradeable(address(scm)).grantRole(scm.MEMBER_REMOVER_ROLE(), address(this));
        scm.removeMember(memberToRemove);
        IAccessControlUpgradeable(address(scm)).revokeRole(scm.MEMBER_REMOVER_ROLE(), address(this));

        // then cancel the rotation operation in the timelock
        CancelTimelockOperation.cancel(l2AddressRegistry.coreGov(), operationId);
    }
}