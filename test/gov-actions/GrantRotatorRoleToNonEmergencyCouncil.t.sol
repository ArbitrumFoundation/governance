// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../src/gov-action-contracts/nonemergency/GrantRotatorRoleToNonEmergencyCouncil.sol";

contract GrantRotatorRoleToNonEmergencyCouncilTest is Test {
    UpgradeExecutor arbOneUe = UpgradeExecutor(0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827);

    function testAction() external {
        vm.skip(!isFork());

        GrantRotatorRoleToNonEmergencyCouncil gac = new GrantRotatorRoleToNonEmergencyCouncil();

        address emergencyCouncil = gac.emergencyCouncil();
        address nonEmergencyCouncil = gac.nonEmergencyCouncil();
        SecurityCouncilManager manager = gac.securityCouncilManager();

        vm.prank(emergencyCouncil);
        arbOneUe.execute(address(gac), abi.encodeWithSignature("perform()"));

        assertTrue(manager.hasRole(gac.MEMBER_ROTATOR_ROLE(), nonEmergencyCouncil));
        assertTrue(manager.hasRole(gac.MEMBER_REPLACER_ROLE(), nonEmergencyCouncil));

        assertFalse(manager.hasRole(gac.MEMBER_ROTATOR_ROLE(), emergencyCouncil));
        assertFalse(manager.hasRole(gac.MEMBER_REPLACER_ROLE(), emergencyCouncil));
    }
}
