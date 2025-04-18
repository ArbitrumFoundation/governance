// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./L2ArbitrumToken.sol";
import "./L2ArbitrumGovernor.sol";
import "./ArbitrumTimelock.sol";
import "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
import "./FixedDelegateErc20Wallet.sol";
import "./ArbitrumDAOConstitution.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

struct DeployCoreParams {
    uint256 _l2MinTimelockDelay;
    address _l1Token;
    uint256 _l2TokenInitialSupply;
    uint256 _votingPeriod;
    uint256 _votingDelay;
    uint256 _coreQuorumThreshold; // 10k denominator
    uint256 _treasuryQuorumThreshold; // 10k denominator
    uint256 _proposalThreshold;
    uint64 _minPeriodAfterQuorum;
    address _l2NonEmergencySecurityCouncil; // 7/12 security council
    address _l2InitialSupplyRecipient;
    address _l2EmergencySecurityCouncil; // 9/12 security council
    bytes32 _constitutionHash;
    uint256 _l2TreasuryMinTimelockDelay;
}

struct DeployTreasuryParams {
    ProxyAdmin _proxyAdmin;
    L2ArbitrumToken _l2Token;
    address _l2TreasuryGovernorLogic;
    address payable _coreGov;
    address _executor;
    uint256 _votingPeriod;
    uint256 _votingDelay;
    uint256 _treasuryQuorumThreshold;
    uint256 _proposalThreshold;
    uint64 _minPeriodAfterQuorum;
    uint256 _l2TreasuryMinTimelockDelay;
}

struct DeployedContracts {
    ProxyAdmin proxyAdmin;
    L2ArbitrumGovernor coreGov;
    ArbitrumTimelock coreTimelock;
    L2ArbitrumToken token;
    UpgradeExecutor executor;
    ArbitrumDAOConstitution arbitrumDAOConstitution;
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
//  - ArbitrumTimelock logic (for core gov)
//  - L2ArbitrumGovernor logic (for core gov)
//  - ArbitrumTimelock logic (for treasury)
//  - FixedDelegateErc20Wallet logic
//  - L2ArbitrumGovernor logic (for treasury)
//  - L2ArbitrumToken logic
//  - UpgradeExecutor logic

/// 2. Then deploy the following (in any order):
///     L1:
///         - L1GoveranceFactory
///         - L1Token logic
///         - Gnosis Safe Multisig 9 of 12 Security Council
///     L2:
///         - L2GovernanceFactory
///         - Gnosis Safe Multisig 9 of 12 Security Council
///         - Gnosis Safe Multisig 7 of 12 Security Council
///
///     L1GoveranceFactory and L2GovernanceFactory deployers will be their respective owners, and will carry out the following steps.
/// 3. Call L2GovernanceFactory.deployStep1
///     - Dependencies: L1-Token address, 7 of 12 multisig (as _l2NonEmergencySecurityCouncil)
///
/// 4. Call L1GoveranceFactory.deployStep2
///     - Dependencies: L1 security council address, L2 Timelock address (deployed in previous step)
///
/// 5. Call L2GovernanceFactory.deployStep3
///     - Dependencies: (Aliased) L1-timelock address (deployed in previous step)
/// 6. From the _l2InitialSupplyRecipient transfer ownership of the L2ArbitrumToken to the UpgradeExecutor
///    Then transfer tokens from _l2InitialSupplyRecipient to the treasury and other token distributor
contract L2GovernanceFactory is Ownable {
    event Deployed(
        L2ArbitrumToken token,
        ArbitrumTimelock coreTimelock,
        L2ArbitrumGovernor coreGoverner,
        L2ArbitrumGovernor treasuryGoverner,
        FixedDelegateErc20Wallet arbTreasury,
        ProxyAdmin proxyAdmin,
        UpgradeExecutor executor,
        ArbitrumDAOConstitution arbitrumDAOConstitution
    );

    enum Step {
        One,
        Three,
        Complete
    }

    address public coreTimelockLogic;
    address public coreGovernorLogic;
    address public treasuryGovernorLogic;
    address public l2TokenLogic;
    address public upgradeExecutorLogic;
    address public proxyAdminLogic;
    address public treasuryTimelockLogic;
    address public treasuryLogic;

    // upExecutor and l2EmergencySecurityCouncil are only intialized after deployStep1
    address public upExecutor;
    address public l2EmergencySecurityCouncil; // 9/12 security council

    Step public step;

    constructor(
        address _coreTimelockLogic,
        address _coreGovernorLogic,
        address _treasuryTimelockLogic,
        address _treasuryLogic,
        address _treasuryGovernorLogic,
        address _l2TokenLogic,
        address _upgradeExecutorLogic
    ) {
        require(_coreTimelockLogic != address(0), "L2GovernanceFactory: null _coreTimelockLogic");
        require(_coreGovernorLogic != address(0), "L2GovernanceFactory: null _coreGovernorLogic");
        require(
            _treasuryTimelockLogic != address(0), "L2GovernanceFactory: null _treasuryTimelockLogic"
        );
        require(_treasuryLogic != address(0), "L2GovernanceFactory: null _treasuryLogic");
        require(
            _treasuryGovernorLogic != address(0), "L2GovernanceFactory: null _treasuryGovernorLogic"
        );
        require(_l2TokenLogic != address(0), "L2GovernanceFactory: null _l2TokenLogic");
        require(
            _upgradeExecutorLogic != address(0), "L2GovernanceFactory: null _upgradeExecutorLogic"
        );

        coreTimelockLogic = _coreTimelockLogic;
        coreGovernorLogic = _coreGovernorLogic;
        treasuryTimelockLogic = _treasuryTimelockLogic;
        treasuryLogic = _treasuryLogic;
        treasuryGovernorLogic = _treasuryGovernorLogic;
        l2TokenLogic = _l2TokenLogic;
        upgradeExecutorLogic = _upgradeExecutorLogic;
        proxyAdminLogic = address(new ProxyAdmin());
        step = Step.One;
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
        // ensure this step isnt run twice
        require(step == Step.One, "L2GovernanceFactory: not step one");
        dc.proxyAdmin = ProxyAdmin(proxyAdminLogic);

        // store it so it can be used in step 3
        l2EmergencySecurityCouncil = params._l2EmergencySecurityCouncil;

        // deploy the timelock
        dc.coreTimelock = deployTimelock(dc.proxyAdmin, coreTimelockLogic);
        dc.coreTimelock.initialize(params._l2MinTimelockDelay, new address[](0), new address[](0));

        dc.executor = deployUpgradeExecutor(dc.proxyAdmin, upgradeExecutorLogic);
        // we make this contract the admin of the upgrade executor for now, then
        // switch that over in step 3
        dc.executor.initialize(address(this), new address[](0));
        upExecutor = address(dc.executor);

        dc.token = deployToken(dc.proxyAdmin, l2TokenLogic);
        dc.token.initialize(
            params._l1Token, params._l2TokenInitialSupply, params._l2InitialSupplyRecipient
        );

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

        dc.arbitrumDAOConstitution = new ArbitrumDAOConstitution(params._constitutionHash);
        dc.arbitrumDAOConstitution.transferOwnership(upExecutor);

        dc.coreTimelock.grantRole(dc.coreTimelock.PROPOSER_ROLE(), address(dc.coreGov));

        bytes32 cancellerRole = dc.coreTimelock.CANCELLER_ROLE();
        dc.coreTimelock.grantRole(cancellerRole, address(dc.coreGov));
        // L2 9/12 council can cancel proposals
        dc.coreTimelock.grantRole(cancellerRole, params._l2EmergencySecurityCouncil);

        // allow the 7/12 security council to schedule actions
        // we don't give _l2NonEmergencySecurityCouncil the canceller role since it shouldn't
        // have the affordance to cancel proposals proposed by others
        dc.coreTimelock.grantRole(
            dc.coreTimelock.PROPOSER_ROLE(), address(params._l2NonEmergencySecurityCouncil)
        );
        // anyone is allowed to execute on the timelock
        dc.coreTimelock.grantRole(dc.coreTimelock.EXECUTOR_ROLE(), address(0));

        // after initialisation revoke admin roles from the timelock
        // and give it to the upgrade executor
        dc.coreTimelock.grantRole(dc.coreTimelock.TIMELOCK_ADMIN_ROLE(), upExecutor);
        // revoke admin roles from the timelock and the deployer
        dc.coreTimelock.revokeRole(dc.coreTimelock.TIMELOCK_ADMIN_ROLE(), address(dc.coreTimelock));
        dc.coreTimelock.revokeRole(dc.coreTimelock.TIMELOCK_ADMIN_ROLE(), address(this));

        DeployedTreasuryContracts memory dtc = deployTreasuryContracts(
            DeployTreasuryParams({
                _proxyAdmin: dc.proxyAdmin,
                _l2Token: dc.token,
                _coreGov: payable(address(dc.coreGov)),
                _l2TreasuryGovernorLogic: treasuryGovernorLogic,
                _executor: address(dc.executor),
                _votingPeriod: params._votingPeriod,
                _votingDelay: params._votingDelay,
                _treasuryQuorumThreshold: params._treasuryQuorumThreshold,
                _proposalThreshold: params._proposalThreshold,
                _minPeriodAfterQuorum: params._minPeriodAfterQuorum,
                _l2TreasuryMinTimelockDelay: params._l2TreasuryMinTimelockDelay
            })
        );

        // give proxyAdmin affordance to upgrade gov contracts (via governance)
        dc.proxyAdmin.transferOwnership(address(dc.executor));

        emit Deployed(
            dc.token,
            dc.coreTimelock,
            dc.coreGov,
            dtc.treasuryGov,
            dtc.arbTreasury,
            dc.proxyAdmin,
            dc.executor,
            dc.arbitrumDAOConstitution
        );

        step = Step.Three;
        return (dc, dtc);
    }

    function deployStep3(address _aliasedL1Timelock) public onlyOwner {
        require(step == Step.Three, "L2GovernanceFactory: not step three");
        // now that we have all the addresses we can grant roles to them on the upgrade executor
        UpgradeExecutor exec = UpgradeExecutor(upExecutor);
        exec.grantRole(exec.EXECUTOR_ROLE(), l2EmergencySecurityCouncil);
        exec.grantRole(exec.EXECUTOR_ROLE(), _aliasedL1Timelock);

        exec.grantRole(exec.ADMIN_ROLE(), upExecutor);
        exec.revokeRole(exec.ADMIN_ROLE(), address(this));
        step = Step.Complete;
    }

    function deployTreasuryContracts(DeployTreasuryParams memory params)
        internal
        returns (DeployedTreasuryContracts memory dtc)
    {
        // The treasury governor doesnt need a timelock, but the L2ArbitrumGovernor
        // requires a timelock, so we add one with 0 delay
        ArbitrumTimelock treasuryTimelock =
            deployTimelock(params._proxyAdmin, treasuryTimelockLogic);
        treasuryTimelock.initialize(
            params._l2TreasuryMinTimelockDelay, new address[](0), new address[](0)
        );

        L2ArbitrumGovernor treasuryGov = deployGovernor(params._proxyAdmin, treasuryGovernorLogic);
        treasuryGov.initialize({
            _token: params._l2Token,
            _timelock: treasuryTimelock,
            _owner: params._executor,
            _votingDelay: params._votingDelay,
            _votingPeriod: params._votingPeriod,
            _quorumNumerator: params._treasuryQuorumThreshold,
            _proposalThreshold: params._proposalThreshold,
            _minPeriodAfterQuorum: params._minPeriodAfterQuorum
        });

        // Only treasury governor can propose
        treasuryTimelock.grantRole(treasuryTimelock.PROPOSER_ROLE(), address(treasuryGov));
        treasuryTimelock.grantRole(treasuryTimelock.CANCELLER_ROLE(), address(treasuryGov));
        // anyone can execute
        treasuryTimelock.grantRole(treasuryTimelock.EXECUTOR_ROLE(), address(0));

        // admin to the executor, all other admin revoked
        treasuryTimelock.grantRole(treasuryTimelock.TIMELOCK_ADMIN_ROLE(), upExecutor);
        treasuryTimelock.revokeRole(
            treasuryTimelock.TIMELOCK_ADMIN_ROLE(), address(treasuryTimelock)
        );
        treasuryTimelock.revokeRole(treasuryTimelock.TIMELOCK_ADMIN_ROLE(), address(this));

        // the actual treasury
        FixedDelegateErc20Wallet arbTreasury = deployTreasury(params._proxyAdmin, treasuryLogic);
        address excludeAddress = treasuryGov.EXCLUDE_ADDRESS();
        // since all actions from the treasury governor are executed through the timelock
        // the timelock is the owner of the treasury
        arbTreasury.initialize(address(params._l2Token), excludeAddress, address(treasuryTimelock));
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
