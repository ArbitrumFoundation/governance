// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./L2ArbitrumToken.sol";
import "./L2ArbitrumGovernor.sol";
import "./ArbitrumTimelock.sol";
import "./UpgradeExecutor.sol";
import "./FixedDelegateErc20Wallet.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// CHRIS: TODO: re review the roles test in the gov factory
// CHRIS: TODO: consider doing some xchain stuff in forge

struct DeployCoreParams {
    uint256 _l2MinTimelockDelay;
    address _l1Token;
    uint256 _l2TokenInitialSupply;
    uint256 _votingPeriod;
    uint256 _votingDelay;
    uint256 _coreQuorumThreshold;
    uint256 _treasuryQuorumThreshold;
    uint256 _proposalThreshold;
    uint64 _minPeriodAfterQuorum;
    address _upgradeProposer; // in addition to core gov
}

struct DeployTreasuryParams {
    ProxyAdmin _proxyAdmin;
    L2ArbitrumToken _token;
    address _l2TreasuryGovernorLogic;
    address payable _coreGov;
    address _executor;
    uint256 _votingPeriod;
    uint256 _votingDelay;
    uint256 _treasuryQuorumThreshold;
    uint256 _proposalThreshold;
    uint64 _minPeriodAfterQuorum;
}

struct DeployedContracts {
    ProxyAdmin proxyAdmin;
    L2ArbitrumGovernor coreGov;
    ArbitrumTimelock coreTimelock;
    L2ArbitrumToken token;
    UpgradeExecutor executor;
}

struct DeployedTreasuryContracts {
    L2ArbitrumGovernor treasuryGov;
    ArbitrumTimelock treasuryTimelock;
    FixedDelegateErc20Wallet arbTreasury;
}

/// @title Factory contract that deploys the L2 components for Arbitrum governance
/// @notice Governance Deployment Steps:
/// 1. Deploy the following pre-requiste logic contracts:
///     L1:
///         - UpgradeExecutor logic
///     L2:
///         - ArbitrumTimelock logic
///         - L2ArbitrumGovernor logic
///         - FixedDelegateErc20 logic
///         - L2ArbitrumToken logic
///         - UpgradeExecutor logic
/// 2. Then deploy the following (in any order):
///     L1:
///         - L1GoveranceFactory
///         - L1Token
///         - Gnosis Safe Multisig 9 of 12 Security Council
///     L2:
///         - L2GovernanceFactory
///         - Gnosis Safe Multisig 9 of 12 Security Council
///         - Gnosis Safe Multisig 7 of 12 Security Council
///
///     L1GoveranceFactory and L2GovernanceFactory deployers will be their respective owners, and will carry out the following steps.
/// 3. Call L2GovernanceFactory.deployStep1
///     - Dependencies: L1-Token address, 7 of 12 multisig (as _upgradeProposer)
///
/// 4. Call L1GoveranceFactory.deployStep2
///     - Dependencies: L1 security council address, L2 Timelock address (deployed in previous step)
///
/// 5. Call L2GovernanceFactory.deployStep3
///     - Dependencies: (Aliased) L1-timelock address (deployed in previous step), L2 security council address (as _l2UpgradeExecutors)
///
contract L2GovernanceFactory is Ownable {
    event Deployed(
        L2ArbitrumToken token,
        ArbitrumTimelock coreTimelock,
        L2ArbitrumGovernor coreGoverner,
        L2ArbitrumGovernor treasuryGoverner,
        FixedDelegateErc20Wallet treasuryTimelock,
        ProxyAdmin proxyAdmin,
        UpgradeExecutor executor
    );

    address public coreTimelockLogic;
    address public coreGovernorLogic;
    address public treasuryGovernorLogic;
    address public l2TokenLogic;
    address public upgradeExecutorLogic;
    address public proxyAdminLogic;
    address public treasuryTimelockLogic;
    address public treasuryLogic;

    address public upExecutor;

    constructor(
        address _coreTimelockLogic,
        address _coreGovernorLogic,
        address _treasuryTimelockLogic,
        address _treasuryLogic,
        address _treasuryGovernorLogic,
        address _l2TokenLogic,
        address _upgradeExecutorLogic
    ) {
        coreTimelockLogic = _coreTimelockLogic;
        coreGovernorLogic = _coreGovernorLogic;
        treasuryTimelockLogic = _treasuryTimelockLogic;
        treasuryLogic = _treasuryLogic;
        treasuryGovernorLogic = _treasuryGovernorLogic;
        l2TokenLogic = _l2TokenLogic;
        upgradeExecutorLogic = _upgradeExecutorLogic;
        proxyAdminLogic = address(new ProxyAdmin());
    }

    function deployStep1(DeployCoreParams memory params)
        public
        virtual
        onlyOwner
        returns (
            DeployedContracts memory deployedCoreContracts,
            DeployedTreasuryContracts memory deployedTreasuryContracts
        )
    {
        DeployedContracts memory dc;

        require(upExecutor == address(0), "L2GovernanceFactory: l2Executor already deployed");
        dc.proxyAdmin = ProxyAdmin(proxyAdminLogic);

        dc.coreTimelock = deployTimelock(dc.proxyAdmin, coreTimelockLogic);
        address[] memory proposers;
        address[] memory executors;
        dc.coreTimelock.initialize(params._l2MinTimelockDelay, proposers, executors);
        dc.executor = deployUpgradeExecutor(dc.proxyAdmin, upgradeExecutorLogic);
        upExecutor = address(dc.executor);

        dc.token = deployToken(dc.proxyAdmin, l2TokenLogic);
        dc.token.initialize(params._l1Token, params._l2TokenInitialSupply, address(dc.executor));

        // give proxyAdmin affordance to upgrade gov contracts (via governance)
        dc.proxyAdmin.transferOwnership(address(dc.executor));

        dc.coreGov = deployGovernor(dc.proxyAdmin, coreGovernorLogic);
        dc.coreGov.initialize({
            _token: dc.token,
            _timelock: dc.coreTimelock,
            _owner: address(dc.executor),
            _votingDelay: params._votingDelay,
            _votingPeriod: params._votingPeriod,
            _quorumNumerator: params._coreQuorumThreshold,
            _proposalThreshold: params._proposalThreshold,
            _minPeriodAfterQuorum: params._minPeriodAfterQuorum
        });

        dc.coreTimelock.grantRole(dc.coreTimelock.PROPOSER_ROLE(), address(dc.coreGov));
        dc.coreTimelock.grantRole(dc.coreTimelock.PROPOSER_ROLE(), address(params._upgradeProposer));
        // anyone is allowed to execute on the timelock
        dc.coreTimelock.grantRole(dc.coreTimelock.EXECUTOR_ROLE(), address(0));

        dc.coreTimelock.grantRole(dc.coreTimelock.CANCELLER_ROLE(), address(dc.coreGov));
        // we don't give _upgradeProposer the canceller role since it shouldn't
        // have the affordance to cancel proposals proposed by others

        // allow the upgrade executor manage roles
        dc.coreTimelock.grantRole(dc.coreTimelock.TIMELOCK_ADMIN_ROLE(), upExecutor);
        // revoke admin roles from the timelock and the deployer
        dc.coreTimelock.revokeRole(dc.coreTimelock.TIMELOCK_ADMIN_ROLE(), address(dc.coreTimelock));
        dc.coreTimelock.revokeRole(dc.coreTimelock.TIMELOCK_ADMIN_ROLE(), address(this));

        DeployedTreasuryContracts memory dtc = deployTreasuryContracts(
            DeployTreasuryParams({
                _proxyAdmin: dc.proxyAdmin,
                _token: dc.token,
                _coreGov: payable(address(dc.coreGov)),
                _l2TreasuryGovernorLogic: treasuryGovernorLogic,
                _executor: address(dc.executor),
                _votingPeriod: params._votingPeriod,
                _votingDelay: params._votingDelay,
                _treasuryQuorumThreshold: params._treasuryQuorumThreshold,
                _proposalThreshold: params._proposalThreshold,
                _minPeriodAfterQuorum: params._minPeriodAfterQuorum
            })
        );
        emit Deployed(
            dc.token,
            dc.coreTimelock,
            dc.coreGov,
            dtc.treasuryGov,
            dtc.arbTreasury,
            dc.proxyAdmin,
            dc.executor
            );
        return (dc, dtc);
    }

    function deployStep3(address[] memory _l2UpgradeExecutors) public onlyOwner {
        require(upExecutor != address(0), "L2GovernanceFactory: l2Executor not yet deployed");
        // initializer reverts if deployStep3 called twice
        UpgradeExecutor(upExecutor).initialize(upExecutor, _l2UpgradeExecutors);
    }

    function deployTreasuryContracts(DeployTreasuryParams memory params)
        internal
        returns (DeployedTreasuryContracts memory dtc)
    {
        ArbitrumTimelock treasuryTimelock =
            deployTimelock(params._proxyAdmin, treasuryTimelockLogic);
        {
            address[] memory proposers;
            address[] memory executors;
            // Gov contrac requires a timelock, so we give it one with 0 delay
            treasuryTimelock.initialize(0, proposers, executors);
        }
        L2ArbitrumGovernor treasuryGov = deployGovernor(params._proxyAdmin, treasuryGovernorLogic);
        treasuryGov.initialize({
            _token: params._token,
            _timelock: treasuryTimelock,
            _owner: params._executor,
            _votingDelay: params._votingDelay,
            _votingPeriod: params._votingPeriod,
            _quorumNumerator: params._treasuryQuorumThreshold,
            _proposalThreshold: params._proposalThreshold,
            _minPeriodAfterQuorum: params._minPeriodAfterQuorum
        });

        // Only treasury can propose, anyone can execute, no admin (revoke defaults)
        treasuryTimelock.grantRole(treasuryTimelock.PROPOSER_ROLE(), address(treasuryGov));
        treasuryTimelock.grantRole(treasuryTimelock.CANCELLER_ROLE(), address(treasuryGov));

        treasuryTimelock.grantRole(treasuryTimelock.EXECUTOR_ROLE(), address(0));

        treasuryTimelock.grantRole(treasuryTimelock.TIMELOCK_ADMIN_ROLE(), upExecutor);

        treasuryTimelock.revokeRole(
            treasuryTimelock.TIMELOCK_ADMIN_ROLE(), address(treasuryTimelock)
        );
        treasuryTimelock.revokeRole(treasuryTimelock.TIMELOCK_ADMIN_ROLE(), address(this));

        FixedDelegateErc20Wallet arbTreasury = deployTreasury(params._proxyAdmin, treasuryLogic);
        address excludeAddress = treasuryGov.EXCLUDE_ADDRESS();
        arbTreasury.initialize(address(params._token), excludeAddress, address(treasuryGov));
        return DeployedTreasuryContracts({
            arbTreasury: arbTreasury,
            treasuryTimelock: treasuryTimelock,
            treasuryGov: treasuryGov
        });
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
        returns (L2ArbitrumToken)
    {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _l2TokenLogic,
            address(_proxyAdmin),
            bytes("")
        );
        return L2ArbitrumToken(address(proxy));
    }

    function deployGovernor(ProxyAdmin _proxyAdmin, address _l2GovernorLogic)
        internal
        returns (L2ArbitrumGovernor)
    {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _l2GovernorLogic,
            address(_proxyAdmin),
            bytes("")
        );
        return L2ArbitrumGovernor(payable(address(proxy)));
    }

    function deployTreasury(ProxyAdmin _proxyAdmin, address _l2TreasuryLogic)
        internal
        returns (FixedDelegateErc20Wallet)
    {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _l2TreasuryLogic,
            address(_proxyAdmin),
            bytes("")
        );
        return FixedDelegateErc20Wallet(payable(address(proxy)));
    }

    function deployTimelock(ProxyAdmin _proxyAdmin, address _l2TimelockLogic)
        internal
        returns (ArbitrumTimelock)
    {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _l2TimelockLogic,
            address(_proxyAdmin),
            bytes("")
        );
        return ArbitrumTimelock(payable(address(proxy)));
    }
}
