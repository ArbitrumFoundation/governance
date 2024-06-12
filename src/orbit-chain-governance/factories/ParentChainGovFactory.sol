// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../L1ArbitrumTimelock.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/// @title Factory that deploys governance chain contracts for cross chain governance
/// @notice Requires core nitro contracts (i.e., inbox), and Upgrade Executor, and a Proxy Admin to
/// be deployed on the parent chain, and a governance timelock be deployed on the governance chain
/// via GovernanceChainGovFactory.
contract ParentChainGovFactory is Ownable {
    bool private done = false;

    event Deployed(L1ArbitrumTimelock timelock, address inbox);

    error AlreadyExecuted();
    error NotAContract(address _address);

    /// @param _parentChainUpExec address of UpgradeExecutor on parent chain
    /// @param _parentChainProxyAdmin address of ProxyAdmin on parent chain
    /// @param _inbox address of governance chain's inbox on parent chain
    /// @param _governanceChainCoreTimelock address of core timelock on governance chain
    /// @param _minTimelockDelay time in seconds after governance-initiated child-to-parent message is executed in the outbox before it can be executed in the timelock
    function deployStep2(
        address _parentChainUpExec,
        address _parentChainProxyAdmin,
        address _inbox,
        address _governanceChainCoreTimelock,
        uint256 _minTimelockDelay
    ) external onlyOwner returns (L1ArbitrumTimelock timelock) {
        if (done) {
            revert AlreadyExecuted();
        }
        done = true;
        // sanity checks
        if (!Address.isContract(_parentChainUpExec)) {
            revert NotAContract(_parentChainUpExec);
        }
        if (!Address.isContract(_parentChainProxyAdmin)) {
            revert NotAContract(_parentChainProxyAdmin);
        }
        if (!Address.isContract(_inbox)) {
            revert NotAContract(_inbox);
        }
        // end sanity checks

        // deploy and init the timelock
        timelock = deployTimelock(ProxyAdmin(_parentChainProxyAdmin));
        timelock.initialize(
            _minTimelockDelay, new address[](0), _inbox, _governanceChainCoreTimelock
        );
        // anyone can execute
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

        // revoke admin rights and give them to the upgrade executor
        timelock.grantRole(timelock.TIMELOCK_ADMIN_ROLE(), address(_parentChainUpExec));
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock));
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(this));

        // grant canceller role to upgrade executor; this can be used e.g. by an admin with executor affordance granted to the upgrade executor
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(_parentChainUpExec));

        emit Deployed(timelock, _inbox);
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
