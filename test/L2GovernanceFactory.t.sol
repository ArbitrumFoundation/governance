// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/L2GovernanceFactory.sol";

import "forge-std/Test.sol";

contract L2GovernanceFactoryTest is Test {
    address l1Addr = address(222);
    uint256 initialSupply = 522;

    function testDoesDeployGovernanceFactory() external {
        L2GovernanceFactory factory = new L2GovernanceFactory();
        (L2ArbitrumToken token, L2ArbitrumGovernor gov, L2ArbitrumTimelock timelock, ProxyAdmin proxyAdmin) =
            factory.deploy(0, l1Addr, initialSupply, address(this));

        assertGt(address(token).code.length, 0, "no token deployed");
    }
}
