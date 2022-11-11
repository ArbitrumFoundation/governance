// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./L2ArbitrumToken.sol";
import "./L2ArbitrumGovernor.sol";
import "./ArbitrumTimelock.sol";
import "./UpgradeExecutor.sol";
import "./ArbTreasury.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Factory contract that deploys the L2 components for Arbitrum governance

/**
 * @notice Governance Deployment Steps:
 * 1. Deploy the following (in any order):
 *     L1:
 *         - L1GoveranceFactory
 *         - L1 -oken
 *         - Gnosis Safe Multisig Security Council
 *     L2:
 *         - L2GovernanceFactory
 *         - Gnosis Safe Multisig Security Council
 *
 *     L1GoveranceFactory and L2GovernanceFactory deployers will be their respective owners, and will carry out the following steps.
 * 2. Call L2GovernanceFactory.deployStep1
 *     - Dependencies: L1-Token address
 *
 * 3. Call L1GoveranceFactory.deployStep2
 *     - Dependencies: L1 security counsil address, L2 Timelock address (deployed in previous step)
 *
 * 4. Call L2GovernanceFactory.deployStep3
 *     - Dependencies: (Aliased) L1-timelock address (deployed in previous step), L2 security council address
 */
struct DeployCoreParams {
    uint256 _l2MinTimelockDelay;
    address _l1Token;
    uint256 _l2TokenInitialSupply;
    address _l2TokenOwner; // DG TODO: Who dis?
    uint256 _votingPeriod;
    uint256 _votingDelay;
    uint256 _coreQuorumThreshold;
    uint256 _treasuryQuorumThreshold;
    uint256 _proposalThreshold;
    uint64 _minPeriodAfterQuorum;
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
    ArbTreasury arbTreasury;
}

contract L2GovernanceFactory is Ownable {
    event Deployed(
        L2ArbitrumToken token,
        ArbitrumTimelock coreTimelock,
        L2ArbitrumGovernor coreGoverner,
        L2ArbitrumGovernor treasuryGoverner,
        ArbTreasury treasuryTimelock,
        ProxyAdmin proxyAdmin,
        UpgradeExecutor executor
    );

    address public l2CoreTimelockLogic;
    address public l2CoreGovernorLogic;
    address public l2TreasuryGovernorLogic;
    address public l2TokenLogic;
    address public l2UpgradeExecutorLogic;
    address public proxyAdminLogic;
    address public l2TreasuryTimelockLogic;
    address public l2TreasuryLogic;

    address public l2Executor;

    constructor() {
        l2CoreTimelockLogic = address(new ArbitrumTimelock());
        l2CoreGovernorLogic = address(new L2ArbitrumGovernor());
        l2TreasuryTimelockLogic = address(new ArbitrumTimelock());
        l2TreasuryLogic = address(new ArbTreasury());
        l2TreasuryGovernorLogic = address(new L2ArbitrumGovernor());
        l2TokenLogic = address(new L2ArbitrumToken());
        l2UpgradeExecutorLogic = address(new UpgradeExecutor());
        // CHRIS: TODO: we dont want the owner of the proxy admin to be this address!
        // CHRIS: TODO: make sure to transfer it out
        // CHRIS: TODO: in both this and the L1gov fac
        proxyAdminLogic = address(new ProxyAdmin());
    }

    // CHRIS: TODO: make this whole thing ownable? we want to avoid the missing steps, but that's not an issue right

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

        require(l2Executor == address(0), "L2GovernanceFactory: l2Executor already deployed");
        dc.proxyAdmin = ProxyAdmin(proxyAdminLogic); // DG TODO:  does this make sense?
        dc.token = deployToken(dc.proxyAdmin, l2TokenLogic);
        dc.token.initialize(params._l1Token, params._l2TokenInitialSupply, params._l2TokenOwner);

        dc.coreTimelock = deployTimelock(dc.proxyAdmin, l2CoreTimelockLogic);
        // CHRIS: TODO: can we remove this?
        {
            address[] memory proposers;
            address[] memory executors;
            dc.coreTimelock.initialize(params._l2MinTimelockDelay, proposers, executors);
        }
        dc.executor = deployUpgradeExecutor(dc.proxyAdmin, l2UpgradeExecutorLogic);
        l2Executor = address(dc.executor);
        dc.executor.preInit(address(this));
        dc.coreGov = deployGovernor(dc.proxyAdmin, l2CoreGovernorLogic);
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

        // the timelock itself and deployer are admins
        // CHRIS: TODO: set the same for the l1 contract?
        dc.coreTimelock.grantRole(dc.coreTimelock.PROPOSER_ROLE(), address(dc.coreGov));
        dc.coreTimelock.grantRole(dc.coreTimelock.EXECUTOR_ROLE(), address(0));
        dc.coreTimelock.revokeRole(dc.coreTimelock.TIMELOCK_ADMIN_ROLE(), address(dc.coreTimelock));
        dc.coreTimelock.revokeRole(dc.coreTimelock.TIMELOCK_ADMIN_ROLE(), address(this));

        DeployedTreasuryContracts memory dtc = deployTreasuryContracts(
            DeployTreasuryParams({
                _proxyAdmin: dc.proxyAdmin,
                _token: dc.token,
                _coreGov: payable(address(dc.coreGov)),
                _l2TreasuryGovernorLogic: l2TreasuryGovernorLogic,
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
        // DG TODO: tests only pass with this explicit return, why
        return (dc, dtc);
    }

    function deployStep3(address[] memory _l2UpgradeExecutors) public onlyOwner {
        require(l2Executor != address(0), "L2GovernanceFactory: l2Executor not yet deployed");
        // initializer reverts if deployStep3 called twice
        UpgradeExecutor(l2Executor).initialize(l2Executor, _l2UpgradeExecutors);
    }

    function deployTreasuryContracts(DeployTreasuryParams memory params)
        internal
        returns (DeployedTreasuryContracts memory dtc)
    {
        ArbitrumTimelock treasuryTimelock =
            deployTimelock(params._proxyAdmin, l2TreasuryTimelockLogic);
        {
            address[] memory proposers;
            address[] memory executors;
            // Gov contrac requires a timelock, so we give it one with 0 delay
            treasuryTimelock.initialize(0, proposers, executors);
        }
        L2ArbitrumGovernor treasuryGov = deployGovernor(params._proxyAdmin, l2TreasuryGovernorLogic);
        treasuryGov.initialize({
            _token: params._token,
            _timelock: treasuryTimelock,
            _owner: params._executor, // DG TODO: ...yes?
            _votingDelay: params._votingDelay, // DG TODO: same as core okay?
            _votingPeriod: params._votingPeriod, // DG TODO: same as core okay?
            _quorumNumerator: params._treasuryQuorumThreshold,
            _proposalThreshold: params._proposalThreshold, // DG TODO: same as core okay?
            _minPeriodAfterQuorum: params._minPeriodAfterQuorum // DG TODO: same as core okay?
        });

        // Only treasury can propose, anyone can execute, no admon (revoke defaults)
        // DG TODO: Sanity check this
        treasuryTimelock.grantRole(treasuryTimelock.PROPOSER_ROLE(), address(treasuryGov));
        treasuryTimelock.grantRole(treasuryTimelock.EXECUTOR_ROLE(), address(0));
        treasuryTimelock.revokeRole(
            treasuryTimelock.TIMELOCK_ADMIN_ROLE(), address(treasuryTimelock)
        );
        treasuryTimelock.revokeRole(treasuryTimelock.TIMELOCK_ADMIN_ROLE(), address(this));

        ArbTreasury arbTreasury = deployTreasury(params._proxyAdmin, l2TreasuryLogic);
        arbTreasury.initialize(payable(address(treasuryGov)));
        return DeployedTreasuryContracts({
            arbTreasury: arbTreasury,
            treasuryTimelock: treasuryTimelock,
            treasuryGov: treasuryGov
        });
    }

    function deployUpgradeExecutor(ProxyAdmin _proxyAdmin, address _upgradeExecutorLogic)
        internal
        returns (UpgradeExecutor upgradeExecutor)
    {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _upgradeExecutorLogic,
            address(_proxyAdmin),
            bytes("")
        );
        upgradeExecutor = UpgradeExecutor(address(proxy));
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

    function deployTreasury(ProxyAdmin _proxyAdmin, address _l2TreasuryLogic)
        internal
        returns (ArbTreasury arbTreasury)
    {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _l2TreasuryLogic,
            address(_proxyAdmin),
            bytes("")
        );
        arbTreasury = ArbTreasury(payable(address(proxy)));
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
