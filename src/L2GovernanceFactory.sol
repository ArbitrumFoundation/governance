// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./L2ArbitrumToken.sol";
import "./L2ArbitrumGovernor.sol";
import "./ArbitrumTimelock.sol";

// @openzeppelin-contracts-upgradeable-0.8 doesn't contain transparent proxies
import "@openzeppelin/contracts-0.8/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-0.8/proxy/transparent/ProxyAdmin.sol";

/// @title Factory contract that deploys the L2 components for Arbitrum governance
contract L2GovernanceFactory {
    event Deployed(
        L2ArbitrumToken _token, ArbitrumTimelock timelock, L2ArbitrumGovernor governor, ProxyAdmin _proxyAdmin
    );

    function deploy(uint256 _minTimelockDelay, address _l1TokenAddress, uint256 _initialSupply, address _owner)
        external
        returns (L2ArbitrumToken token, L2ArbitrumGovernor gov, ArbitrumTimelock timelock, ProxyAdmin proxyAdmin)
    {
        proxyAdmin = new ProxyAdmin();

        token = deployToken(proxyAdmin);
        token.initialize(_l1TokenAddress, _initialSupply, _owner);

        timelock = deployTimelock(proxyAdmin);
        address[] memory proposers;
        address[] memory executors;
        timelock.initialize(_minTimelockDelay, proposers, executors);

        // the timelock itself and deployer are admins
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock));
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(this));

        gov = deployGovernor(proxyAdmin);
        gov.initialize(token, timelock);

        emit Deployed(token, timelock, gov, proxyAdmin);
    }

    function deployToken(ProxyAdmin _proxyAdmin) internal returns (L2ArbitrumToken token) {
        address logic = address(new L2ArbitrumToken());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(logic, address(_proxyAdmin), bytes(""));
        token = L2ArbitrumToken(address(proxy));
    }

    function deployGovernor(ProxyAdmin _proxyAdmin) internal returns (L2ArbitrumGovernor gov) {
        address logic = address(new L2ArbitrumGovernor());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(logic, address(_proxyAdmin), bytes(""));
        gov = L2ArbitrumGovernor(payable(address(proxy)));
    }

    function deployTimelock(ProxyAdmin _proxyAdmin) internal returns (ArbitrumTimelock timelock) {
        address logic = address(new ArbitrumTimelock());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(logic, address(_proxyAdmin), bytes(""));
        timelock = ArbitrumTimelock(payable(address(proxy)));
    }
}
