// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../src/gov-action-contracts/AIPs/NomineeGovernorV2UpgradeAction.sol";
import "../../src/security-council-mgmt/governors/SecurityCouncilNomineeElectionGovernor.sol";

contract AIPXActionTest is Test {
    address oldImplementation = 0x8436A1bc9f9f9EB0cF1B51942C5657b60A40CCDD;
    SecurityCouncilNomineeElectionGovernor gov = SecurityCouncilNomineeElectionGovernor(payable(0x8a1cDA8dee421cD06023470608605934c16A05a0));
    ProxyAdmin proxyAdmin = ProxyAdmin(0xdb216562328215E010F819B5aBe947bad4ca961e);
    UpgradeExecutor arbOneUe = UpgradeExecutor(0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827);
    address council = 0x423552c0F05baCCac5Bfa91C6dCF1dc53a0A1641;
    IArbitrumDAOConstitution constitution = IArbitrumDAOConstitution(0x1D62fFeB72e4c360CcBbacf7c965153b00260417);
    bytes32 newConstitutionHash = 0x0101010101010101010101010101010101010101010101010101010101010101;

    address newImplementation = address(new SecurityCouncilNomineeElectionGovernor());
    uint256 votingDelay = 7 days;
    NomineeGovernorV2UpgradeActionTemplate action = new NomineeGovernorV2UpgradeActionTemplate(
        address(proxyAdmin),
        address(gov),
        newImplementation,
        votingDelay,
        address(constitution),
        newConstitutionHash
    );

    function testAction() external {
        if (!_isForkTest()) {
            console.log("not fork test, skipping AIPXActionTest");
            return;
        }

        if (_getImplementation() != oldImplementation) {
            console.log("implementation not set to old implementation, skipping AIPXActionTest");
            return;
        }

        vm.prank(council);
        arbOneUe.execute(address(action), abi.encodeWithSelector(action.perform.selector));

        assertEq(
            gov.votingDelay(),
            votingDelay,
            "voting delay not set"
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
        return proxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(gov)));
    }

    function _isForkTest() internal view returns (bool) {
        bool isForkTest;
        address _gov = address(gov);
        assembly {
            isForkTest := gt(extcodesize(_gov), 0)
        }
        return isForkTest;
    }
}
