// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../util/TestUtil.sol";

import "../../../src/security-council-mgmt/governors/SecurityCouncilNomineeElectionGovernor.sol";

contract SecurityCouncilNomineeElectionGovernorTest is Test {
    SecurityCouncilNomineeElectionGovernor governor;

    SecurityCouncilNomineeElectionGovernor.InitParams initParams = SecurityCouncilNomineeElectionGovernor.InitParams({
        targetNomineeCount: 6,
        firstNominationStartDate: SecurityCouncilNomineeElectionGovernorTiming.Date({year: 2030, month: 1, day: 1, hour: 0}),
        nomineeVettingDuration: 1 days,
        nomineeVetter: address(0x11),
        securityCouncilManager: ISecurityCouncilManager(address(0x22)),
        securityCouncilMemberElectionGovernor: SecurityCouncilMemberElectionGovernor(payable(address(0x33))),
        token: IVotesUpgradeable(address(0x44)),
        owner: address(0x55),
        quorumNumeratorValue: 10,
        votingPeriod: 1 days
    });

    address proxyAdmin = address(0x66);
    address proposer = address(0x77);


    function setUp() public {
        governor = _deployGovernor();

        governor.initialize(initParams);
    }

    // helpers

    function _voter(uint8 i) internal pure returns (address) {
        return address(uint160(0x1100 + i));
    }

    function _nominee(uint8 i) internal pure returns (address) {
        return address(uint160(0x2200 + i));
    }

    function _mockGetPastVotes(address account, uint256 votes, uint256 blockNumber) internal {
        vm.mockCall(
            address(initParams.token),
            abi.encodeWithSelector(initParams.token.getPastVotes.selector, account, blockNumber),
            abi.encode(votes)
        );
    }

    function _mockGetPastVotes(address account, uint256 votes) internal {
        vm.mockCall(
            address(initParams.token),
            abi.encodeWithSelector(initParams.token.getPastVotes.selector, account),
            abi.encode(votes)
        );
    }

    function _propose() internal returns (uint256) {
        // we need to mock getPastVotes for the proposer
        _mockGetPastVotes({account: address(proposer), votes: 0});

        vm.prank(proposer);
        return governor.createElection();
    }

    function _deployGovernor() internal returns (SecurityCouncilNomineeElectionGovernor) {
        return SecurityCouncilNomineeElectionGovernor(
            payable(
                new TransparentUpgradeableProxy(
                    address(new SecurityCouncilNomineeElectionGovernor()),
                    proxyAdmin,
                    bytes("")
                )
            )
        );
    }
}
