// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../src/gov-action-contracts/AIPs/SecurityCouncilMgmt/RotateMembersUpgradeAction.sol";
import "../../src/gov-action-contracts/governance/CancelTimelockAndRemoveMemberAction.sol";
import "../../src/security-council-mgmt/SecurityCouncilManager.sol";
import "../../src/gov-action-contracts/address-registries/L2AddressRegistry.sol";

contract CancelTimelockAndRemoveMemberActionTest is Test {
    address oldImplementation = 0x468dA0eE5570Bdb1Dd81bFd925BAf028A93Dce64;
    ProxyAdmin proxyAdmin = ProxyAdmin(0xdb216562328215E010F819B5aBe947bad4ca961e);
    address council = 0x423552c0F05baCCac5Bfa91C6dCF1dc53a0A1641;
    UpgradeExecutor arbOneUe = UpgradeExecutor(0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827);
    IArbitrumDAOConstitution constitution =
        IArbitrumDAOConstitution(0x1D62fFeB72e4c360CcBbacf7c965153b00260417);

    function setUp() public {
        string memory arbRpc = vm.envOr("ARB_RPC_URL", string(""));
        if (bytes(arbRpc).length != 0) {
            vm.createSelectFork(arbRpc);
        }
    }

    function testAction() external {
        if (!_isForkTest()) {
            console.log("not fork test, skipping RotateMembersUpgradeActionTest");
            return;
        }

        // we need to deploy a new registry
        L2AddressRegistry reg = new L2AddressRegistry(
            IL2ArbitrumGoverner(0xf07DeD9dC292157749B6Fd268E37DF6EA38395B9),
            IL2ArbitrumGoverner(0x789fC99093B09aD01C34DC7251D0C89ce743e5a4),
            IFixedDelegateErc20Wallet(0xF3FC178157fb3c87548bAA86F9d24BA38E649B58),
            constitution,
            proxyAdmin,
            ISecurityCouncilNomineeElectionGovernor(0x8a1cDA8dee421cD06023470608605934c16A05a0)
        );
        // ensure that the scm has been updated
        ensureLatestScm(reg);

        // rotate one of the members
        ISecurityCouncilManager scm = reg.securityCouncilManager();
        address[] memory fc = scm.getFirstCohort();
        assertEq(fc.length, 6, "Not 6 addresses in first cohort");
        address memberOut = fc[2];
        uint256 memberInKey = 137;
        address memberIn = vm.addr(memberInKey);

        // sign the rotation hash
        bytes memory sig;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                memberInKey, scm.getRotateMemberHash(memberOut, scm.rotationNonce(memberOut))
            );
            sig = abi.encodePacked(r, s, v);
        }

        vm.recordLogs();
        address memberElectionGov = address(reg.scMemberElectionGovernor());
        vm.prank(memberOut);
        scm.rotateMember(memberIn, memberElectionGov, sig);

        // use the event to get the data we need for cancelling
        // we do minimal checks here since we know what the transaction looked
        // like in a live situation more verification would need to be done to ensure
        // the correct proposal id and member to remove
        address memberToRemove;
        bytes32 proposalId;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(scm)) {
                // first log is the member rotation
                // event MemberRotated(address indexed replacedAddress, address indexed newAddress, Cohort cohort);
                memberToRemove = address(uint160(uint256(logs[i].topics[2])));
            } else if (logs[i].emitter == address(reg.coreGovTimelock())) {
                // second log is call scheduled
                // event CallScheduled(
                //     bytes32 indexed id,
                //     uint256 indexed index,
                //     address target,
                //     uint256 value,
                //     bytes data,
                //     bytes32 predecessor,
                //     uint256 delay
                // );
                proposalId = logs[i].topics[1];
            } else {
                revert("Unrecognised log");
            }
        }
        assertTrue(reg.coreGovTimelock().isOperation(proposalId), "Prop does not exist");

        CancelTimelockAndRemoveMemberAction action = new CancelTimelockAndRemoveMemberAction(reg);
        vm.prank(council);
        arbOneUe.execute(
            address(action), abi.encodeCall(action.perform, (memberToRemove, proposalId))
        );

        address[] memory fc1 = scm.getFirstCohort();
        assertEq(fc1.length, 5, "Not 5 addresses in first cohort");
        assertFalse(reg.coreGovTimelock().isOperation(proposalId), "Prop does not exist");
        for (uint256 i = 0; i < 6; i++) {
            if (i == 0 || i == 1 || i == 3 || i == 4) {
                assertEq(fc[i], fc1[i]);
            } else if (i == 2) {
                // do nothing this has been removed
            } else if (i == 5) {
                // last place has moved to 2
                assertEq(fc[i], fc1[2]);
            } else {
                revert("Unexpected case");
            }
        }
    }

    function ensureLatestScm(L2AddressRegistry reg) internal {
        address newImplementation = address(new SecurityCouncilManager());
        address rotationSetter = address(1337);
        uint256 minRotationPeriod = 1 weeks;
        RotateMembersUpgradeAction action = new RotateMembersUpgradeAction(
            reg, newImplementation, minRotationPeriod, rotationSetter
        );
        vm.prank(council);
        arbOneUe.execute(address(action), abi.encodeWithSelector(action.perform.selector));
    }

    function _isForkTest() internal view returns (bool) {
        return address(arbOneUe).code.length > 0;
    }
}
