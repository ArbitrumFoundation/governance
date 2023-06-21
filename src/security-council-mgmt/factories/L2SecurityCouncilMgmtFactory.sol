// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../governors/SecurityCouncilMemberElectionGovernor.sol";
import "../governors/SecurityCouncilNomineeElectionGovernor.sol";
import "../SecurityCouncilManager.sol";
import "./SecurityCouncilUpgradeExecutorFactory.sol";
import "./AddressAliasHelper.sol";
import "../SecurityCouncilMemberRemoverGov.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../interfaces/ISecurityCouncilManager.sol";
import "../interfaces/ISecurityCouncilMemberRemoverGov.sol";
import "../../ArbitrumTimelock.sol";
import "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

struct DeployParams {
    address _govChainEmergencySecurityCouncil;
    address _govChainNonEmergencySecurityCouncil;
    address _l1SecurityCouncilUpdateRouter;
    address _proxyAdmin;
    address[] _marchCohort;
    address[] _septemberCohort;
    address l2UpgradeExecutor;
    address arbToken;
    uint256 _removalGovMinTimelockDelay;
    uint256 _removalGovVotingDelay;
    uint256 _removalGovVotingPeriod;
    uint256 _removalGovQuorumNumerator;
    uint256 _removalGovProposalThreshold;
    uint64 _removalGovMinPeriodAfterQuorum;

    // governor params
    Cohort firstCohort;
    uint256 firstNominationStartTime;
    uint256 nominationFrequency;
    uint256 nomineeVettingDuration;
    address nomineeVetter;
    uint256 nomineeQuorumNumerator;
    uint256 nomineeVotingPeriod;

    uint256 memberVotingPeriod;
    uint256 memberFullWeightDurationNumerator;
    uint256 memberDecreasingWeightDurationNumerator;
    uint256 memberDurationDenominator;
}

/// @notice Factory for deploying L2 Security Council management contracts

contract L2SecurityCouncilMgmtFactory is Ownable {
    event ContractsDeployed(DeployedContracts deployedContracts);

    struct DeployedContracts {
        SecurityCouncilNomineeElectionGovernor nomineeElectionGovernor;
        SecurityCouncilMemberElectionGovernor memberElectionGovernor;
        ISecurityCouncilManager securityCouncilManager;
        address l2EmergencySecurityCouncilUpgradeExecutor;
        address l2NonEmergencySecurityCouncilUpgradeExecutor;
        ISecurityCouncilMemberRemoverGov securityCouncilMemberRemoverGov;
    }

    function deployStep2(DeployParams memory dp)
        external
        onlyOwner
        returns (DeployedContracts memory)
    {
        require(
            Address.isContract(dp._govChainEmergencySecurityCouncil),
            "L2SecurityCouncilMgmtFactory: _govChainEmergencySecurityCouncil is not a contract"
        );
        require(
            Address.isContract(dp._govChainNonEmergencySecurityCouncil),
            "L2SecurityCouncilMgmtFactory: _govChainNonEmergencySecurityCouncil is not a contract"
        );
        require(
            Address.isContract(dp._proxyAdmin),
            "L2SecurityCouncilMgmtFactory: _proxyAdmin is not a contract"
        );
        require(
            Address.isContract(dp.l2UpgradeExecutor),
            "L2SecurityCouncilMgmtFactory: l2UpgradeExecutor is not a contract"
        );
        require(
            Address.isContract(dp.arbToken),
            "L2SecurityCouncilMgmtFactory: arbToken is not a contract"
        );
        require(
            dp._removalGovQuorumNumerator != 0,
            "L2SecurityCouncilMgmtFactory: _removalGovQuorumNumerator is 0"
        );

        DeployedContracts memory deployedContracts;

        // deploy nominee election governor
        deployedContracts.nomineeElectionGovernor = SecurityCouncilNomineeElectionGovernor(
            payable(
                new TransparentUpgradeableProxy(
                    address(new SecurityCouncilNomineeElectionGovernor()),
                    dp._proxyAdmin,
                    bytes("")
                )
            )
        );

        // deploy member election governor
        deployedContracts.memberElectionGovernor = SecurityCouncilMemberElectionGovernor(
            payable(
                new TransparentUpgradeableProxy(
                    address(new SecurityCouncilMemberElectionGovernor()),
                    dp._proxyAdmin,
                    bytes("")
                )
            )
        );

        // deploy security council manager
        deployedContracts.securityCouncilManager = ISecurityCouncilManager(
            address(
                new TransparentUpgradeableProxy(
                address(new SecurityCouncilManager()),
                dp._proxyAdmin,
                bytes(""))
            )
        );

        // deploy a security council upgrade executor factory; we use it to deplouy an upgrade executor for both security councils
        SecurityCouncilUpgradeExecutorFactory securityCouncilUpgradeExecutorFactory =
            new SecurityCouncilUpgradeExecutorFactory();

        deployedContracts.l2EmergencySecurityCouncilUpgradeExecutor = securityCouncilUpgradeExecutorFactory
            .deploy({
            securityCouncil: IGnosisSafe(dp._govChainEmergencySecurityCouncil),
            securityCouncilUpdator: address(deployedContracts.securityCouncilManager),
            proxyAdmin: dp._proxyAdmin,
            upgradeExecutorAdmin: dp.l2UpgradeExecutor
        });

        deployedContracts.l2NonEmergencySecurityCouncilUpgradeExecutor = securityCouncilUpgradeExecutorFactory
            .deploy({
            securityCouncil: IGnosisSafe(dp._govChainNonEmergencySecurityCouncil),
            securityCouncilUpdator: address(deployedContracts.securityCouncilManager),
            proxyAdmin: dp._proxyAdmin,
            upgradeExecutorAdmin: dp.l2UpgradeExecutor
        });

        // deploy security council member remover gov
        deployedContracts.securityCouncilMemberRemoverGov = ISecurityCouncilMemberRemoverGov(
            address(
                new TransparentUpgradeableProxy(
                address(new SecurityCouncilMemberRemoverGov()),
                dp._proxyAdmin,
                bytes("")
                )
            )
        );
        address[] memory memberRemovers = new address[](2);
        memberRemovers[0]  = dp._govChainEmergencySecurityCouncil;
        memberRemovers[1] = address(deployedContracts.securityCouncilMemberRemoverGov);

        Roles memory roles = Roles({
            admin: dp.l2UpgradeExecutor,
            cohortUpdator: address(deployedContracts.memberElectionGovernor),
            memberAdder: dp._govChainEmergencySecurityCouncil,
            memberRemovers: memberRemovers,
            memberRotator: dp._govChainEmergencySecurityCouncil
        });

        TargetContracts memory targetContracts = TargetContracts({
            govChainEmergencySecurityCouncilUpgradeExecutor: deployedContracts.l2EmergencySecurityCouncilUpgradeExecutor,
            govChainNonEmergencySecurityCouncilUpgradeExecutor: deployedContracts.l2NonEmergencySecurityCouncilUpgradeExecutor,
            l1SecurityCouncilUpdateRouter: dp._l1SecurityCouncilUpdateRouter
        });

        // initialize securityCouncilManager
        deployedContracts.securityCouncilManager.initialize(
            dp._marchCohort, dp._septemberCohort, roles, targetContracts
        );

        ArbitrumTimelock memberRemovalGovTimelock = ArbitrumTimelock(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                    address(new ArbitrumTimelock()),
                    dp._proxyAdmin,
                    bytes("")
                    )
                )
            )
        );

        memberRemovalGovTimelock.initialize(
            dp._removalGovMinTimelockDelay, new address[](0), new address[](0)
        );
        // removal gov can propose
        memberRemovalGovTimelock.grantRole(
            memberRemovalGovTimelock.PROPOSER_ROLE(), address(deployedContracts.securityCouncilMemberRemoverGov)
        );
        // anyone can execute
        memberRemovalGovTimelock.grantRole(memberRemovalGovTimelock.EXECUTOR_ROLE(), address(0));

        // DAO (upgrade executor) is admin
        memberRemovalGovTimelock.grantRole(
            memberRemovalGovTimelock.TIMELOCK_ADMIN_ROLE(), dp.l2UpgradeExecutor
        );
        // TODO do we need to revoke the TIMELOCK_ADMIN_ROLE from the timelock itself?

        _initRemovalGov(
            dp, deployedContracts.securityCouncilManager, memberRemovalGovTimelock, deployedContracts.securityCouncilMemberRemoverGov
        );

        _initElectionGovernors(
            dp, deployedContracts.securityCouncilManager, deployedContracts.nomineeElectionGovernor, deployedContracts.memberElectionGovernor
        );

        emit ContractsDeployed(deployedContracts);
        return deployedContracts;
    }

    function _initRemovalGov(
        DeployParams memory dp,
        ISecurityCouncilManager _securityCouncilManager,
        ArbitrumTimelock _memberRemovalGovTimelock,
        ISecurityCouncilMemberRemoverGov securityCouncilMemberRemoverGov
    ) internal {
        securityCouncilMemberRemoverGov.initialize({
            _proposer: dp._govChainEmergencySecurityCouncil,
            _securityCouncilManager: _securityCouncilManager,
            _token: IVotesUpgradeable(dp.arbToken),
            _timelock: _memberRemovalGovTimelock,
            _owner: dp.l2UpgradeExecutor,
            _votingDelay: dp._removalGovVotingDelay,
            _votingPeriod: dp._removalGovVotingPeriod,
            _quorumNumerator: dp._removalGovQuorumNumerator,
            _proposalThreshold: dp._removalGovProposalThreshold,
            _minPeriodAfterQuorum: dp._removalGovMinPeriodAfterQuorum
        });
    }

    function _initElectionGovernors(
        DeployParams memory dp,
        ISecurityCouncilManager securityCouncilManager,
        SecurityCouncilNomineeElectionGovernor nomineeElectionGovernor,
        SecurityCouncilMemberElectionGovernor memberElectionGovernor
    ) internal {
        nomineeElectionGovernor.initialize(SecurityCouncilNomineeElectionGovernor.InitParams({
            targetNomineeCount: dp._marchCohort.length,
            firstCohort: dp.firstCohort,
            firstNominationStartTime: dp.firstNominationStartTime,
            nominationFrequency: dp.nominationFrequency,
            nomineeVettingDuration: dp.nomineeVettingDuration,
            nomineeVetter: dp.nomineeVetter,
            securityCouncilManager: securityCouncilManager,
            securityCouncilMemberElectionGovernor: memberElectionGovernor,
            token: IVotesUpgradeable(dp.arbToken),
            owner: dp.l2UpgradeExecutor,
            quorumNumeratorValue: dp.nomineeQuorumNumerator,
            votingPeriod: dp.nomineeVotingPeriod
        }));
        
        memberElectionGovernor.initialize({
            _nomineeElectionGovernor: nomineeElectionGovernor,
            _securityCouncilManager: securityCouncilManager,
            _token: IVotesUpgradeable(dp.arbToken),
            _owner: dp.l2UpgradeExecutor,
            _votingPeriod: dp.memberVotingPeriod,
            _maxNominees: dp._marchCohort.length,
            _fullWeightDurationNumerator: dp.memberFullWeightDurationNumerator,
            _decreasingWeightDurationNumerator: dp.memberDecreasingWeightDurationNumerator,
            _durationDenominator: dp.memberDurationDenominator
        });
    }
}
