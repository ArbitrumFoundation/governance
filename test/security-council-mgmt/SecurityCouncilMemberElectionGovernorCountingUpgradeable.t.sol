// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../src/security-council-mgmt/governors/SecurityCouncilMemberElectionGovernor.sol";

contract SecurityCouncilMemberElectionGovernorCountingUpgradeableTest is Test {
    SecurityCouncilMemberElectionGovernor governor;
    uint256 constant n = 500;
    uint256 constant k = 6;

    function setUp() public {
        governor = new SecurityCouncilMemberElectionGovernor();

        // todo: initialize
    }

    function testSelectTopNominees() public {
        // make the worst case array (N in ascending order)
        address[] memory nominees = new address[](n);
        uint256[] memory weights = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            nominees[i] = address(uint160(i + 1));
            weights[i] = i + 1;
        }

        // select the top 6 and calculate gas usage
        uint256 g = gasleft();
        address[] memory topNominees = governor.selectTopNominees(nominees, weights, k);
        g = g - gasleft();

        // check the result
        for (uint256 i = 0; i < k; i++) {
            assertEq(topNominees[i], address(uint160(n - k + 1 + i)));
        }

        assertLt(g, n * 2000);
    }
}
