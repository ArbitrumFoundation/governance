// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../src/gov-action-contracts/nonemergency/SwitchManagerRolesAction.sol";

contract SwitchManagerRolesActionTest is Test {
    UpgradeExecutor arbOneUe = UpgradeExecutor(0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827);

    function testAction() external {
        if (!isFork()) {
            console.log("not fork test, skipping SwitchManagerRolesActionTest");
            return;
        }

        SwitchManagerRolesAction gac = new SwitchManagerRolesAction();

        address emergencyCouncil = gac.emergencyCouncil();
        address nonEmergencyCouncil = gac.nonEmergencyCouncil();
        SecurityCouncilManager manager = gac.securityCouncilManager();

        vm.prank(0xf7951D92B0C345144506576eC13Ecf5103aC905a); // L1 Timelock Alias
        arbOneUe.execute(address(gac), abi.encodeWithSignature("perform()"));

        assertTrue(manager.hasRole(manager.MEMBER_ADDER_ROLE(), nonEmergencyCouncil));
        assertTrue(manager.hasRole(manager.MEMBER_REPLACER_ROLE(), nonEmergencyCouncil));
        assertTrue(manager.hasRole(manager.MEMBER_ROTATOR_ROLE(), nonEmergencyCouncil));
        assertTrue(manager.hasRole(manager.MEMBER_REMOVER_ROLE(), nonEmergencyCouncil));

        assertFalse(manager.hasRole(manager.MEMBER_ADDER_ROLE(), emergencyCouncil));
        assertFalse(manager.hasRole(manager.MEMBER_REPLACER_ROLE(), emergencyCouncil));
        assertFalse(manager.hasRole(manager.MEMBER_ROTATOR_ROLE(), emergencyCouncil));
        assertFalse(manager.hasRole(manager.MEMBER_REMOVER_ROLE(), emergencyCouncil));
    }
}
