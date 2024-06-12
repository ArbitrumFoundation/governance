// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../security-council-mgmt/SecurityCouncilManager.sol";

/// @notice Grant the non emergency council the MEMBER_ADDER_ROLE, MEMBER_REPLACER_ROLE, MEMBER_ROTATOR_ROLE and MEMBER_REMOVER_ROLE on the SecurityCouncilManager.
///         Revoke those same roles from the emergency council.
contract SwitchManagerRolesAction {
    SecurityCouncilManager public constant securityCouncilManager =
        SecurityCouncilManager(0xD509E5f5aEe2A205F554f36E8a7d56094494eDFC);

    address public constant nonEmergencyCouncil = 0xADd68bCb0f66878aB9D37a447C7b9067C5dfa941;
    address public constant emergencyCouncil = 0x423552c0F05baCCac5Bfa91C6dCF1dc53a0A1641;

    bytes32 public immutable MEMBER_ADDER_ROLE = securityCouncilManager.MEMBER_ADDER_ROLE();
    bytes32 public immutable MEMBER_REPLACER_ROLE = securityCouncilManager.MEMBER_REPLACER_ROLE();
    bytes32 public immutable MEMBER_ROTATOR_ROLE = securityCouncilManager.MEMBER_ROTATOR_ROLE();
    bytes32 public immutable MEMBER_REMOVER_ROLE = securityCouncilManager.MEMBER_REMOVER_ROLE();

    function perform() public {
        // grant roles to non emergency council
        securityCouncilManager.grantRole(MEMBER_ADDER_ROLE, nonEmergencyCouncil);
        securityCouncilManager.grantRole(MEMBER_REPLACER_ROLE, nonEmergencyCouncil);
        securityCouncilManager.grantRole(MEMBER_ROTATOR_ROLE, nonEmergencyCouncil);
        securityCouncilManager.grantRole(MEMBER_REMOVER_ROLE, nonEmergencyCouncil);

        // revoke roles from emergency council
        securityCouncilManager.revokeRole(MEMBER_ADDER_ROLE, emergencyCouncil);
        securityCouncilManager.revokeRole(MEMBER_REPLACER_ROLE, emergencyCouncil);
        securityCouncilManager.revokeRole(MEMBER_ROTATOR_ROLE, emergencyCouncil);
        securityCouncilManager.revokeRole(MEMBER_REMOVER_ROLE, emergencyCouncil);

        // ensure roles were changed
        require(securityCouncilManager.hasRole(MEMBER_ADDER_ROLE, nonEmergencyCouncil), "Adder role not granted");
        require(securityCouncilManager.hasRole(MEMBER_REPLACER_ROLE, nonEmergencyCouncil), "Replacer role not granted");
        require(securityCouncilManager.hasRole(MEMBER_ROTATOR_ROLE, nonEmergencyCouncil), "Rotator role not granted");
        require(securityCouncilManager.hasRole(MEMBER_REMOVER_ROLE, nonEmergencyCouncil), "Remover role not granted");

        require(!securityCouncilManager.hasRole(MEMBER_ADDER_ROLE, emergencyCouncil), "Adder role not revoked");
        require(!securityCouncilManager.hasRole(MEMBER_REPLACER_ROLE, emergencyCouncil), "Replacer role not revoked");
        require(!securityCouncilManager.hasRole(MEMBER_ROTATOR_ROLE, emergencyCouncil), "Rotator role not revoked");
        require(!securityCouncilManager.hasRole(MEMBER_REMOVER_ROLE, emergencyCouncil), "Remover role not revoked");
    }
}
