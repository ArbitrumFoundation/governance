// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./L2ArbitrumToken.sol";
import "./L2ArbitrumGovernor.sol";
import "./ArbitrumTimelock.sol";

// @openzeppelin-contracts-upgradeable doesn't contain transparent proxies
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @title Factory contract that deploys the L1 components for Arbitrum governance
contract L1GovernanceFactory {
    event Deployed(ArbitrumTimelock timelock, ProxyAdmin _proxyAdmin);

    function deploy(uint256 _minTimelockDelay) external returns (ArbitrumTimelock timelock, ProxyAdmin proxyAdmin) {
        proxyAdmin = new ProxyAdmin();

        timelock = deployTimelock(proxyAdmin);
        address[] memory proposers;
        address[] memory executors;
        timelock.initialize(_minTimelockDelay, proposers, executors);

        // the timelock itself and deployer are admins
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(this));
        // we want the L1 timelock to be able to upgrade itself
        // timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock));

        emit Deployed(timelock, proxyAdmin);
    }

    function deployTimelock(ProxyAdmin _proxyAdmin) internal returns (ArbitrumTimelock timelock) {
        address logic = address(new ArbitrumTimelock());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(logic, address(_proxyAdmin), bytes(""));
        timelock = ArbitrumTimelock(payable(address(proxy)));
    }
}
