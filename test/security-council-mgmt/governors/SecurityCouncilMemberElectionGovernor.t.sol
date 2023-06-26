// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../util/TestUtil.sol";

import "../../../src/security-council-mgmt/governors/SecurityCouncilMemberElectionGovernor.sol";

contract SecurityCouncilMemberElectionGovernorTest is Test {
    struct InitParams {
        SecurityCouncilNomineeElectionGovernor nomineeElectionGovernor;
        ISecurityCouncilManager securityCouncilManager;
        IVotesUpgradeable token;
        address owner;
        uint256 votingPeriod;
        uint256 maxNominees;
        uint256 fullWeightDurationNumerator;
        uint256 decreasingWeightDurationNumerator;
        uint256 durationDenominator;
    }

    SecurityCouncilMemberElectionGovernor governor;
    address proxyAdmin = address(100);

    InitParams initParams = InitParams({
        nomineeElectionGovernor: SecurityCouncilNomineeElectionGovernor(payable(address(1))),
        securityCouncilManager: ISecurityCouncilManager(address(2)),
        token: IVotesUpgradeable(address(3)),
        owner: address(4),
        votingPeriod: 5,
        maxNominees: 6,
        fullWeightDurationNumerator: 7,
        decreasingWeightDurationNumerator: 8,
        durationDenominator: 7 + 8
    });

    function setUp() public {
        governor = _deployGovernor();

        governor.initialize({
            _nomineeElectionGovernor: initParams.nomineeElectionGovernor,
            _securityCouncilManager: initParams.securityCouncilManager,
            _token: initParams.token,
            _owner: initParams.owner,
            _votingPeriod: initParams.votingPeriod,
            _maxNominees: initParams.maxNominees,
            _fullWeightDurationNumerator: initParams.fullWeightDurationNumerator,
            _decreasingWeightDurationNumerator: initParams.decreasingWeightDurationNumerator,
            _durationDenominator: initParams.durationDenominator
        });
    }

    function testProperInitialization() public {
        assertEq(
            address(governor.nomineeElectionGovernor()), address(initParams.nomineeElectionGovernor)
        );
        assertEq(
            address(governor.securityCouncilManager()), address(initParams.securityCouncilManager)
        );
        assertEq(address(governor.token()), address(initParams.token));
        assertEq(governor.owner(), initParams.owner);
        assertEq(governor.votingPeriod(), initParams.votingPeriod);
        assertEq(governor.maxNominees(), initParams.maxNominees);
        assertEq(governor.fullWeightDurationNumerator(), initParams.fullWeightDurationNumerator);
        assertEq(
            governor.decreasingWeightDurationNumerator(),
            initParams.decreasingWeightDurationNumerator
        );
        assertEq(governor.durationDenominator(), initParams.durationDenominator);
    }

    function testProposeReverts() public {
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernor: Proposing is not allowed, call proposeFromNomineeElectionGovernor instead"
        );
        governor.propose(new address[](0), new uint256[](0), new bytes[](0), "");

        // should also fail if called by the nominee election governor
        vm.prank(address(initParams.nomineeElectionGovernor));
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernor: Proposing is not allowed, call proposeFromNomineeElectionGovernor instead"
        );
        governor.propose(new address[](0), new uint256[](0), new bytes[](0), "");
    }

    function testOnlyNomineeElectionGovernorCanPropose() public {
        vm.expectRevert(
            "SecurityCouncilMemberElectionGovernor: Only the nominee election governor can call this function"
        );
        governor.proposeFromNomineeElectionGovernor();

        // we need to mock call to the nominee election governor
        // electionCount() returns 1
        vm.mockCall(
            address(initParams.nomineeElectionGovernor),
            abi.encodeWithSelector(initParams.nomineeElectionGovernor.electionCount.selector),
            abi.encode(1)
        );

        vm.prank(address(initParams.nomineeElectionGovernor));
        governor.proposeFromNomineeElectionGovernor();
    }

    
    function _deployGovernor() internal returns (SecurityCouncilMemberElectionGovernor) {
        return SecurityCouncilMemberElectionGovernor(
            payable(
                new TransparentUpgradeableProxy(
                    address(new SecurityCouncilMemberElectionGovernor()),
                    proxyAdmin,
                    bytes("")
                )
            )
        );
    }
}
