// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

// import "./L2ArbitrumToken.sol";
// import "./L2ArbitrumGovernor.sol";
import "./L1ArbitrumTimelock.sol";

// @openzeppelin-contracts-upgradeable doesn't contain transparent proxies
import "@openzeppelin/contracts-0.8/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-0.8/proxy/transparent/ProxyAdmin.sol";
import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

/// @title Factory contract that deploys the L1 components for Arbitrum governance
contract L1GovernanceFactory {
    event Deployed(L1ArbitrumTimelock timelock, ProxyAdmin proxyAdmin);

    function deploy(uint256 _minTimelockDelay, address inbox, address l2Timelock, address l2Forwarder)
        external
        returns (L1ArbitrumTimelock timelock, ProxyAdmin proxyAdmin)
    {
        proxyAdmin = new ProxyAdmin();

        timelock = deployTimelock(proxyAdmin);
        address[] memory proposers;
        address[] memory executors;
        timelock.initialize(_minTimelockDelay, proposers, executors, inbox, l2Timelock, l2Forwarder);

        // CHRIS: TODO: we need to grant a role for the receiver

        // CHRIS: TODO: review access control on each of the contracts, and defo the timelocks
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

        // the timelock itself and deployer are admins
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(this));
        // CHRIS: TODO: why? we should better explain this
        // we want the L1 timelock to be able to upgrade itself
        // timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock));

        emit Deployed(timelock, proxyAdmin);

        // CHRIS: TODO: we should full describe the flow of doing an upgrade somewhere
    }

    function deployTimelock(ProxyAdmin _proxyAdmin) internal returns (L1ArbitrumTimelock timelock) {
        address logic = address(new L1ArbitrumTimelock());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(logic, address(_proxyAdmin), bytes(""));
        timelock = L1ArbitrumTimelock(payable(address(proxy)));
    }
}
