// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./L2ArbitrumToken.sol";
import "./L2ArbitrumGovernor.sol";
import "./ArbitrumTimelock.sol";
import "./TreasuryGovTimelock.sol";
import "./UpgradeExecutor.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @title Factory contract that deploys the L2 components for Arbitrum governance

struct DeployCoreParams {
    uint256 _l2MinTimelockDelay;
    address _l1Token;
    uint256 _l2TokenInitialSupply;
    address _l2TokenOwner;
    address[] _l2UpgradeExecutors;
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

contract L2GovernanceFactory {
    event Deployed(
        L2ArbitrumToken token,
        ArbitrumTimelock coreTimelock,
        L2ArbitrumGovernor coreGoverner,
        L2ArbitrumGovernor treasuryGoverner,
        ArbitrumTimelock treasuryTimelock,
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
    address private deployer;

    constructor() {
        l2CoreTimelockLogic = address(new ArbitrumTimelock());
        l2CoreGovernorLogic = address(new L2ArbitrumGovernor());
        l2TreasuryGovernorLogic = address(new L2ArbitrumGovernor());
        l2TokenLogic = address(new L2ArbitrumToken());
        l2UpgradeExecutorLogic = address(new UpgradeExecutor());
        // CHRIS: TODO: we dont want the owner of the proxy admin to be this address!
        // CHRIS: TODO: make sure to transfer it out
        // CHRIS: TODO: in both this and the L1gov fac
        proxyAdminLogic = address(new ProxyAdmin());
        deployer = msg.sender;
    }

    // CHRIS: TODO: make this whole thing ownable? we want to avoid the missing steps, but that's not an issue right

    function deploy(DeployCoreParams memory params)
        public
        virtual
        returns (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            L2ArbitrumGovernor treasuryGov,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor
        )
    {
        require(msg.sender == deployer, "NOT_DEPLOYER");
        require(l2TreasuryTimelockLogic == address(0), "ALREADY_DEPLOYED");

        // DG TODO:  does this make sense?
        proxyAdmin = ProxyAdmin(proxyAdminLogic);
        token = deployToken(proxyAdmin, l2TokenLogic);
        token.initialize(params._l1Token, params._l2TokenInitialSupply, params._l2TokenOwner);

        ArbitrumTimelock coreTimelock = deployTimelock(proxyAdmin, l2CoreTimelockLogic);
        // CHRIS: TODO: can we remove this?
        {
            address[] memory proposers;
            address[] memory executors;
            coreTimelock.initialize(params._l2MinTimelockDelay, proposers, executors);
        }
        executor = deployUpgradeExecutor(proxyAdmin, l2UpgradeExecutorLogic);
        executor.initialize(address(executor), params._l2UpgradeExecutors);
        coreGov = deployGovernor(proxyAdmin, l2CoreGovernorLogic);
        coreGov.initialize({
            _token: token,
            _timelock: coreTimelock,
            _owner: address(executor),
            _votingDelay: params._votingDelay,
            _votingPeriod: params._votingPeriod,
            _quorumNumerator: params._coreQuorumThreshold,
            _proposalThreshold: params._proposalThreshold,
            _minPeriodAfterQuorum: params._minPeriodAfterQuorum
        });

        // the timelock itself and deployer are admins
        // CHRIS: TODO: set the same for the l1 contract?
        coreTimelock.grantRole(coreTimelock.PROPOSER_ROLE(), address(coreGov));
        coreTimelock.grantRole(coreTimelock.EXECUTOR_ROLE(), address(0));
        coreTimelock.revokeRole(coreTimelock.TIMELOCK_ADMIN_ROLE(), address(coreTimelock));
        coreTimelock.revokeRole(coreTimelock.TIMELOCK_ADMIN_ROLE(), address(this));

        (L2ArbitrumGovernor treasuryGov, ArbitrumTimelock treasuryTimelock) = deployTreasury(
            DeployTreasuryParams({
                _proxyAdmin: proxyAdmin,
                _token: token,
                _coreGov: payable(address(coreGov)),
                _l2TreasuryGovernorLogic: l2TreasuryGovernorLogic,
                _executor: address(executor),
                _votingPeriod: params._votingPeriod,
                _votingDelay: params._votingDelay,
                _treasuryQuorumThreshold: params._treasuryQuorumThreshold,
                _proposalThreshold: params._proposalThreshold,
                _minPeriodAfterQuorum: params._minPeriodAfterQuorum
            })
        );
        emit Deployed(
            token, coreTimelock, coreGov, treasuryGov, treasuryTimelock, proxyAdmin, executor
            );
        // DG TODO: tests only pass with this explicit return, why
        return (token, coreGov, treasuryGov, proxyAdmin, executor);
    }

    function deployTreasury(DeployTreasuryParams memory params)
        internal
        returns (L2ArbitrumGovernor treasuryGov, ArbitrumTimelock treasuryTimelock)
    {
        address _treasuryTimelockLogic = address(new TreasuryGovTimelock(params._coreGov));
        l2TreasuryTimelockLogic = _treasuryTimelockLogic;
        treasuryTimelock = deployTimelock(params._proxyAdmin, l2TreasuryTimelockLogic);
        {
            address[] memory proposers;
            address[] memory executors;
            // Gov contrac requires a timelock, so we give it one with 0 delay
            treasuryTimelock.initialize(0, proposers, executors);
        }
        treasuryGov = deployGovernor(params._proxyAdmin, l2TreasuryGovernorLogic);
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
