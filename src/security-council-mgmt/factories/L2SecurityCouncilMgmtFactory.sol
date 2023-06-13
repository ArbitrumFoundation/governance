// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
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
}
/// @notice Factory for deploying L2 Security Council management contracts

contract L2SecurityCouncilMgmtFactory is Ownable {
    event ContractsDeployed(
        address emergencySecurityCouncilUpgradeExecutor,
        address nonEmergencySecurityCouncilUpgradeExecutor,
        address securityCouncilRemovalGov,
        address securityCouncilManager
    );

    function deployStep2(DeployParams memory dp)
        external
        onlyOwner
        returns (address, address, address, address)
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

        // TODO election deployment

        // deploy security council manager
        ISecurityCouncilManager securityCouncilManager = ISecurityCouncilManager(
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

        address l2EmergencySecurityCouncilUpgradeExecutor = securityCouncilUpgradeExecutorFactory
            .deploy({
            securityCouncil: IGnosisSafe(dp._govChainEmergencySecurityCouncil),
            securityCouncilUpdator: address(securityCouncilManager),
            proxyAdmin: dp._proxyAdmin,
            upgradeExecutorAdmin: dp.l2UpgradeExecutor
        });

        address l2NonEmergencySecurityCouncilUpgradeExecutor = securityCouncilUpgradeExecutorFactory
            .deploy({
            securityCouncil: IGnosisSafe(dp._govChainNonEmergencySecurityCouncil),
            securityCouncilUpdator: address(securityCouncilManager),
            proxyAdmin: dp._proxyAdmin,
            upgradeExecutorAdmin: dp.l2UpgradeExecutor
        });

        // deploy security council member remover gov
        ISecurityCouncilMemberRemoverGov securityCouncilMemberRemoverGov =
        ISecurityCouncilMemberRemoverGov(
            address(
                new TransparentUpgradeableProxy(
                address(new SecurityCouncilMemberRemoverGov()),
                dp._proxyAdmin,
                bytes("")
                )
            )
        );

        Roles memory roles = Roles({
            admin: dp.l2UpgradeExecutor,
            cohortUpdator: address(0xdead), // TODO election contract
            memberAdder: dp._govChainEmergencySecurityCouncil,
            memberRemover: address(securityCouncilMemberRemoverGov),
            memberRotator: dp._govChainEmergencySecurityCouncil
        });

        TargetContracts memory targetContracts = TargetContracts({
            govChainEmergencySecurityCouncilUpgradeExecutor: l2EmergencySecurityCouncilUpgradeExecutor,
            govChainNonEmergencySecurityCouncilUpgradeExecutor: l2NonEmergencySecurityCouncilUpgradeExecutor,
            l1SecurityCouncilUpdateRouter: dp._l1SecurityCouncilUpdateRouter
        });

        // initialize securityCouncilManager
        securityCouncilManager.initialize(
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
            memberRemovalGovTimelock.PROPOSER_ROLE(), address(securityCouncilMemberRemoverGov)
        );
        // anyone can execute
        memberRemovalGovTimelock.grantRole(memberRemovalGovTimelock.EXECUTOR_ROLE(), address(0));

        // DAO (upgrade executor) is admin
        memberRemovalGovTimelock.grantRole(
            memberRemovalGovTimelock.TIMELOCK_ADMIN_ROLE(), dp.l2UpgradeExecutor
        );
        // TODO do we need to revoke the TIMELOCK_ADMIN_ROLE from the timelock itself?

        _initRemovalGov(
            dp, securityCouncilManager, memberRemovalGovTimelock, securityCouncilMemberRemoverGov
        );
        emit ContractsDeployed(
            l2EmergencySecurityCouncilUpgradeExecutor,
            l2NonEmergencySecurityCouncilUpgradeExecutor,
            address(securityCouncilMemberRemoverGov),
            address(securityCouncilManager)
        );
        return (
            l2EmergencySecurityCouncilUpgradeExecutor,
            l2NonEmergencySecurityCouncilUpgradeExecutor,
            address(securityCouncilMemberRemoverGov),
            address(securityCouncilManager)
        );
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
}
