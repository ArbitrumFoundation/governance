// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./L2ArbitrumToken.sol";
import "./L2ArbitrumGovernor.sol";
import "./ArbitrumTimelock.sol";
import "./UpgradeExecutor.sol";

// @openzeppelin-contracts-upgradeable doesn't contain transparent proxies
import "@openzeppelin/contracts-0.8/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-0.8/proxy/transparent/ProxyAdmin.sol";

/// @title Factory contract that deploys the L2 components for Arbitrum governance
contract L2GovernanceFactory {
    event Deployed(
        L2ArbitrumToken token,
        ArbitrumTimelock timelock,
        L2ArbitrumGovernor governor,
        ProxyAdmin proxyAdmin,
        UpgradeExecutor executor
    );

    // CHRIS: TODO: make this whole thing ownable? we want to avoid the missing steps, but that's not an issue right

    function deploy(
        uint256 _l2MinTimelockDelay,
        address _l1TokenAddress,
        address _l2TokenLogic,
        uint256 _l2TokenInitialSupply,
        address _l2TokenOwner,
        address _l2TimeLockLogic,
        address _l2GovernorLogic,
        address _l2UpgradeExecutorLogic,
        address _l2UpgradeExecutorInitialOwner
    )
        external
        returns (
            L2ArbitrumToken token,
            L2ArbitrumGovernor gov,
            ArbitrumTimelock timelock,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor
        )
    {
        // CHRIS: TODO: we dont want the owner of the proxy admin to be this address!
        // CHRIS: TODO: make sure to transfer it out
        // CHRIS: TODO: in both this and the L1gov fac
        proxyAdmin = new ProxyAdmin();

        token = deployToken(proxyAdmin, _l2TokenLogic);
        token.initialize(_l1TokenAddress, _l2TokenInitialSupply, _l2TokenOwner);

        timelock = deployTimelock(proxyAdmin, _l2TimeLockLogic);
        address[] memory proposers;
        address[] memory executors;
        timelock.initialize(_l2MinTimelockDelay, proposers, executors);

        gov = deployGovernor(proxyAdmin, _l2GovernorLogic);
        gov.initialize(token, timelock);

        // the timelock itself and deployer are admins
        // CHRIS: TODO: set the same for the l1 contract?
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(gov));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock));
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(this));

        executor = deployUpgradeExecutor(proxyAdmin, _l2UpgradeExecutorLogic);
        executor.initialize(_l2UpgradeExecutorInitialOwner);

        emit Deployed(token, timelock, gov, proxyAdmin, executor);
    }

    function deployUpgradeExecutor(ProxyAdmin _proxyAdmin, address _upgradeExecutorLogic)
        internal
        returns (UpgradeExecutor)
    {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(_upgradeExecutorLogic, address(_proxyAdmin), bytes(""));
        return UpgradeExecutor(address(proxy));
    }

    function deployToken(ProxyAdmin _proxyAdmin, address _l2TokenLogic) internal returns (L2ArbitrumToken token) {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(_l2TokenLogic, address(_proxyAdmin), bytes(""));
        token = L2ArbitrumToken(address(proxy));
    }

    function deployGovernor(ProxyAdmin _proxyAdmin, address _l2GovernorLogic)
        internal
        returns (L2ArbitrumGovernor gov)
    {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(_l2GovernorLogic, address(_proxyAdmin), bytes(""));
        gov = L2ArbitrumGovernor(payable(address(proxy)));
    }

    function deployTimelock(ProxyAdmin _proxyAdmin, address _l2TimelockLogic)
        internal
        returns (ArbitrumTimelock timelock)
    {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(_l2TimelockLogic, address(_proxyAdmin), bytes(""));
        timelock = ArbitrumTimelock(payable(address(proxy)));
    }
}
