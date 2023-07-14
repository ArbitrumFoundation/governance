// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../src/security-council-mgmt/governors/SecurityCouncilMemberRemovalGovernor.sol";
import "../../src/security-council-mgmt/interfaces/ISecurityCouncilManager.sol";

import "../../src/ArbitrumTimelock.sol";
import "../../src/L2ArbitrumToken.sol";
import "./../util/TestUtil.sol";

import "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";

contract MockSecurityCouncilManager {
    function firstCohortIncludes(address x) external returns (bool) {
        return true;
    }
}

contract SecurityCouncilMemberRemovalGovernorTest is Test {
    address l1TokenAddress = address(137);
    uint256 initialTokenSupply = 50_000;
    address tokenOwner = address(238);
    uint256 votingPeriod = 180_000;
    uint256 votingDelay = 0;
    address excludeListMember = address(339);
    uint256 quorumNumerator = 500;
    uint256 proposalThreshold = 0;
    uint64 initialVoteExtension = 5;

    address[] stubAddressArray = [address(640)];
    address someRando = address(741);
    address executor = address(842);
    uint256 _voteSuccessNumerator = 2;
    ISecurityCouncilManager securityCouncilManager;
    SecurityCouncilMemberRemovalGovernor securityCouncilMemberRemovalGovernor;

    address memberToRemove = address(999_999);

    function setUp() public returns (SecurityCouncilMemberRemovalGovernor) {
        L2ArbitrumToken token =
            L2ArbitrumToken(TestUtil.deployProxy(address(new L2ArbitrumToken())));
        token.initialize(l1TokenAddress, initialTokenSupply, tokenOwner);

        ArbitrumTimelock timelock =
            ArbitrumTimelock(payable(TestUtil.deployProxy(address(new ArbitrumTimelock()))));
        timelock.initialize(1, stubAddressArray, stubAddressArray);

        securityCouncilMemberRemovalGovernor = SecurityCouncilMemberRemovalGovernor(
            payable(TestUtil.deployProxy(address(new SecurityCouncilMemberRemovalGovernor())))
        );

        securityCouncilManager = ISecurityCouncilManager(address(new MockSecurityCouncilManager()));
        securityCouncilMemberRemovalGovernor.initialize(
            _voteSuccessNumerator,
            securityCouncilManager,
            token,
            timelock,
            executor,
            votingDelay,
            votingPeriod,
            quorumNumerator,
            proposalThreshold,
            initialVoteExtension
        );
        return securityCouncilMemberRemovalGovernor;
    }

    function testSuccessfulProposalAndCantAbstain() public {
        address[] memory targets = new address[](1);
        targets[0] = address(securityCouncilManager);

        uint256[] memory values = new uint256[](1);

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] =
            abi.encodeWithSelector(ISecurityCouncilManager.removeMember.selector, memberToRemove);

        string memory description = "xyz";

        uint256 proposalId =
            securityCouncilMemberRemovalGovernor.propose(targets, values, calldatas, description);

        // securityCouncilMemberRemovalGovernor.castVote(proposalId, 2);
    }

}
