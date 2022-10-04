// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/L1GovernanceFactory.sol";
import "../src/L2GovernanceFactory.sol";

import "forge-std/Test.sol";

contract xChainGovernanceTest is Test {
    uint256 initialSupply = 10 * 10**9;
    uint256 l1TimelockDelay = 10;
    uint256 l2TimelockDelay = 15;

    function testDoesDeployGovernanceContracts() external {
        L1GovernanceFactory l1Factory = new L1GovernanceFactory();
        L2GovernanceFactory l2Factory = new L2GovernanceFactory();

        (ArbitrumTimelock l1Timelock, ProxyAdmin l1ProxyAdmin) = l1Factory.deploy(l1TimelockDelay);

        // no L1 token available yet
        address l1TokenAddr = address(1);
        (L2ArbitrumToken token, L2ArbitrumGovernor gov, ArbitrumTimelock l2Timelock, ProxyAdmin l2ProxyAdmin) =
            l2Factory.deploy(l2TimelockDelay, l1TokenAddr, initialSupply, address(this));

        assertGt(address(token).code.length, 0, "no token deployed");
    }
}
