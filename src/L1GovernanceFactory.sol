// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

// CHRIS: TODO: review access control on each of the contracts, and defo the timelocks
// CHRIS: TODO: more docs on the factories
// CHRIS: TODO: check the factories match the diagrams

import "./L1ArbitrumTimelock.sol";
import "./UpgradeExecutor.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Factory contract that deploys the L1 components for Arbitrum governance
contract L1GovernanceFactory is Ownable {
    event Deployed(L1ArbitrumTimelock timelock, ProxyAdmin proxyAdmin, UpgradeExecutor executor);

    bool private done = false;

    function deployStep2(
        address upgradeExecutorLogic,
        uint256 _minTimelockDelay,
        address inbox,
        address l2Timelock,
        address l1SecurityCouncil
    )
        external
        onlyOwner
        returns (L1ArbitrumTimelock timelock, ProxyAdmin proxyAdmin, UpgradeExecutor executor)
    {
        require(!done, "L1GovernanceFactory: already executed");
        done = true;
        proxyAdmin = new ProxyAdmin();

        timelock = deployTimelock(proxyAdmin);
        address[] memory executors;
        timelock.initialize(_minTimelockDelay, executors, inbox, l2Timelock);

        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

        executor = deployUpgradeExecutor(proxyAdmin, upgradeExecutorLogic);
        address[] memory upgradeExecutors = new address[](2);
        upgradeExecutors[0] = address(timelock);
        upgradeExecutors[1] = l1SecurityCouncil;
        executor.initialize(address(executor), upgradeExecutors);

        // revoke admin rights and give them to the upgrade executor
        timelock.grantRole(timelock.TIMELOCK_ADMIN_ROLE(), address(executor));
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock));
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(this));

        // DG: TODO: double check / add to diagram
        proxyAdmin.transferOwnership(address(executor));

        emit Deployed(timelock, proxyAdmin, executor);
    }

    function deployUpgradeExecutor(ProxyAdmin _proxyAdmin, address upgradeExecutorLogic)
        internal
        returns (UpgradeExecutor)
    {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(upgradeExecutorLogic, address(_proxyAdmin), bytes(""));
        return UpgradeExecutor(address(proxy));
    }

    function deployTimelock(ProxyAdmin _proxyAdmin)
        internal
        returns (L1ArbitrumTimelock timelock)
    {
        address logic = address(new L1ArbitrumTimelock());
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(logic, address(_proxyAdmin), bytes(""));
        timelock = L1ArbitrumTimelock(payable(address(proxy)));
    }
}
