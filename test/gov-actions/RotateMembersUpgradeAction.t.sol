// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../src/gov-action-contracts/AIPs/SecurityCouncilMgmt/RotateMembersUpgradeAction.sol";
import "../../src/security-council-mgmt/SecurityCouncilManager.sol";
import "../../src/gov-action-contracts/address-registries/L2AddressRegistry.sol";

contract RotateMembersUpgradeActionTest is Test {
    SecurityCouncilManager scm = SecurityCouncilManager(0xD509E5f5aEe2A205F554f36E8a7d56094494eDFC);
    address oldImplementation = 0x468dA0eE5570Bdb1Dd81bFd925BAf028A93Dce64;
    ProxyAdmin proxyAdmin = ProxyAdmin(0xdb216562328215E010F819B5aBe947bad4ca961e);
    address council = 0x423552c0F05baCCac5Bfa91C6dCF1dc53a0A1641;
    UpgradeExecutor arbOneUe = UpgradeExecutor(0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827);
    IArbitrumDAOConstitution constitution = IArbitrumDAOConstitution(0x1D62fFeB72e4c360CcBbacf7c965153b00260417);
    bytes32 newConstitutionHash = keccak256("testy");

    function setUp() public {
        string memory arbRpc = vm.envOr("ARB_RPC_URL", string(""));
        if(bytes(arbRpc).length != 0) {
            vm.createSelectFork(arbRpc);
            vm.rollFork(260227814);
        }
    }

    function testAction() external {         
        if (!_isForkTest()) {
            console.log("not fork test, skipping RotateMembersUpgradeActionTest");
            return;
        }

        if (_getImplementation() != oldImplementation) {
            console.log("implementation not set to old implementation, skipping RotateMembersUpgradeActionTest");
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
        
        address newImplementation = address(new SecurityCouncilManager());
        address rotationSetter = address(137);
        uint256 minRotationPeriod = 1 weeks;

        RotateMembersUpgradeAction action = new RotateMembersUpgradeAction(
            reg, 
            newImplementation,
            minRotationPeriod,
            rotationSetter
        );

        vm.prank(council);
        arbOneUe.execute(address(action), abi.encodeWithSelector(action.perform.selector));

        assertEq(
            scm.minRotationPeriod(),
            minRotationPeriod,
            "min rotation period"
        );
        assertTrue(
            IAccessControlUpgradeable(address(scm)).hasRole(scm.MIN_ROTATION_PERIOD_SETTER_ROLE(), rotationSetter),
            "Min rotation period setter not set"
        );
        assertEq(
            _getImplementation(),
            newImplementation,
            "implementation not set"
        );
        assertEq(
            constitution.constitutionHash(),
            newConstitutionHash,
            "constitution hash not set"
        );
    }

    function _getImplementation() internal view returns (address) {
        return proxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(scm))));
    }

    function _isForkTest() internal view returns (bool) {
        return address(scm).code.length > 0;
    }
}
