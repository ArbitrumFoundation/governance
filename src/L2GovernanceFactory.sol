// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./L2ArbitrumToken.sol";
import "./L2ArbitrumGovernor.sol";
import "./ArbitrumTimelock.sol";
import "./UpgradeExecutor.sol";

// @openzeppelin-contracts-upgradeable doesn't contain transparent proxies
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @title Factory contract that deploys the L2 components for Arbitrum governance

struct DeployParams {
    uint256 _l2MinTimelockDelay;
    address _l1TokenAddress;
    address _l2TokenLogic;
    uint256 _l2TokenInitialSupply;
    address _l2TokenOwner;
    address _l2TimeLockLogic;
    address _l2GovernorLogic;
    address _l2UpgradeExecutorLogic;
    address[] _l2UpgradeExecutors;
    uint256 _votingPeriod;
    uint256 _votingDelay;
    uint256 _quorumThreshold;
    uint256 _proposalThreshold;
    uint64 _minPeriodAfterQuorum;
}

contract L2GovernanceFactory {
    event Deployed(
        L2ArbitrumToken token,
        ArbitrumTimelock timelock,
        L2ArbitrumGovernor governor,
        ProxyAdmin proxyAdmin,
        UpgradeExecutor executor
    );

    // CHRIS: TODO: make this whole thing ownable? we want to avoid the missing steps, but that's not an issue right

    function deploy(DeployParams memory params)
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

        token = deployToken(proxyAdmin, params._l2TokenLogic);
        token.initialize(params._l1TokenAddress, params._l2TokenInitialSupply, params._l2TokenOwner);

        timelock = deployTimelock(proxyAdmin, params._l2TimeLockLogic);
        // CHRIS: TODO: can we remove this?
        {
            address[] memory proposers;
            address[] memory executors;
            timelock.initialize(params._l2MinTimelockDelay, proposers, executors);
        }
        executor = deployUpgradeExecutor(proxyAdmin, params._l2UpgradeExecutorLogic);

        executor.initialize(address(executor), params._l2UpgradeExecutors);
        // todo
        gov = deployGovernor(proxyAdmin, params._l2GovernorLogic);
        gov.initialize(
            token,
            timelock,
            address(executor),
            params._votingDelay,
            params._votingPeriod,
            params._quorumThreshold,
            params._proposalThreshold,
            params._minPeriodAfterQuorum
        );

        // the timelock itself and deployer are admins
        // CHRIS: TODO: set the same for the l1 contract?
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(gov));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock));
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(this));

        emit Deployed(token, timelock, gov, proxyAdmin, executor);
    }

    function deployUpgradeExecutor(ProxyAdmin _proxyAdmin, address _upgradeExecutorLogic)
        internal
        returns (UpgradeExecutor)
    {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _upgradeExecutorLogic,
            address(_proxyAdmin),
            bytes("")
        );
        return UpgradeExecutor(address(proxy));
    }

    function deployToken(ProxyAdmin _proxyAdmin, address _l2TokenLogic)
        internal
        returns (L2ArbitrumToken token)
    {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _l2TokenLogic,
            address(_proxyAdmin),
            bytes("")
        );
        token = L2ArbitrumToken(address(proxy));
    }

    function deployGovernor(ProxyAdmin _proxyAdmin, address _l2GovernorLogic)
        internal
        returns (L2ArbitrumGovernor gov)
    {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _l2GovernorLogic,
            address(_proxyAdmin),
            bytes("")
        );
        gov = L2ArbitrumGovernor(payable(address(proxy)));
    }

    function deployTimelock(ProxyAdmin _proxyAdmin, address _l2TimelockLogic)
        internal
        returns (ArbitrumTimelock timelock)
    {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _l2TimelockLogic,
            address(_proxyAdmin),
            bytes("")
        );
        timelock = ArbitrumTimelock(payable(address(proxy)));
    }
}
