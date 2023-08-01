// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../governors/SecurityCouncilMemberElectionGovernor.sol";
import "../governors/SecurityCouncilNomineeElectionGovernor.sol";
import "../SecurityCouncilManager.sol";
import "../governors/SecurityCouncilMemberRemovalGovernor.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../interfaces/ISecurityCouncilManager.sol";
import "../interfaces/IGnosisSafe.sol";
import "../../ArbitrumTimelock.sol";
import "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import "../../UpgradeExecRouteBuilder.sol";
import "../Common.sol";

struct DeployParams {
    ChainAndUpExecLocation[] upgradeExecutors;
    address govChainEmergencySecurityCouncil;
    address l1ArbitrumTimelock;
    address l2CoreGovTimelock;
    address govChainProxyAdmin;
    address[] secondCohort;
    address[] firstCohort;
    address l2UpgradeExecutor;
    address arbToken;
    uint256 l1TimelockMinDelay;
    uint256 removalGovVotingDelay;
    uint256 removalGovVotingPeriod;
    uint256 removalGovQuorumNumerator;
    uint256 removalGovProposalThreshold;
    uint256 removalGovVoteSuccessNumerator;
    uint64 removalGovMinPeriodAfterQuorum;
    uint256 removalProposalExpirationBlocks;
    SecurityCouncilData[] securityCouncils;
    Date firstNominationStartDate;
    uint256 nomineeVettingDuration;
    address nomineeVetter;
    uint256 nomineeQuorumNumerator;
    uint256 nomineeVotingPeriod;
    uint256 memberVotingPeriod;
    uint256 fullWeightDuration;
}

struct ContractImplementations {
    address nomineeElectionGovernor;
    address memberElectionGovernor;
    address securityCouncilManager;
    address securityCouncilMemberRemoverGov;
}

/// @notice Factory for deploying L2 Security Council management contracts.
/// Prerequisites: core Arb DAO governance contracts, and a SecurityCouncilMemberSyncAction deployed for each governed security council (on each corresponding chain)
contract L2SecurityCouncilMgmtFactory is Ownable {
    event ContractsDeployed(DeployedContracts deployedContracts);

    // contracts deployed by factory
    struct DeployedContracts {
        SecurityCouncilNomineeElectionGovernor nomineeElectionGovernor;
        SecurityCouncilMemberElectionGovernor memberElectionGovernor;
        ISecurityCouncilManager securityCouncilManager;
        SecurityCouncilMemberRemovalGovernor securityCouncilMemberRemoverGov;
        UpgradeExecRouteBuilder upgradeExecRouteBuilder;
    }

    error AddressNotInCouncil(address[] securityCouncil, address account);
    error InvalidCohortsSize(uint256 councilSize, uint256 firstCohortSize, uint256 secondCohortSize);

    /// @dev deploys a transparent proxy for the given implementation contract
    function _deployProxy(address proxyAdmin, address impl, bytes memory initData)
        internal
        returns (address)
    {
        return address(new TransparentUpgradeableProxy(impl, proxyAdmin, initData));
    }

    /// @notice deploys the L2 Security Council management contracts
    /// @param  dp the deployment parameters
    /// @param  impls contract implementations to deploy proxies for
    function deploy(DeployParams memory dp, ContractImplementations memory impls)
        external
        onlyOwner
        returns (DeployedContracts memory)
    {
        if (!Address.isContract(dp.govChainEmergencySecurityCouncil)) {
            revert NotAContract(dp.govChainEmergencySecurityCouncil);
        }

        if (!Address.isContract(dp.govChainProxyAdmin)) {
            revert NotAContract(dp.govChainProxyAdmin);
        }

        if (!Address.isContract(dp.l2UpgradeExecutor)) {
            revert NotAContract(dp.l2UpgradeExecutor);
        }

        if (!Address.isContract(dp.arbToken)) {
            revert NotAContract(dp.arbToken);
        }

        if (dp.nomineeVetter == address(0)) {
            revert ZeroAddress();
        }
        IGnosisSafe govChainEmergencySCSafe = IGnosisSafe(dp.govChainEmergencySecurityCouncil);
        address[] memory owners = govChainEmergencySCSafe.getOwners();
        if (owners.length != (dp.firstCohort.length + dp.secondCohort.length)) {
            revert InvalidCohortsSize(owners.length, dp.firstCohort.length, dp.secondCohort.length);
        }

        for (uint256 i = 0; i < dp.firstCohort.length; i++) {
            if (!govChainEmergencySCSafe.isOwner(dp.firstCohort[i])) {
                revert AddressNotInCouncil(owners, dp.firstCohort[i]);
            }
        }

        for (uint256 i = 0; i < dp.secondCohort.length; i++) {
            if (!govChainEmergencySCSafe.isOwner(dp.secondCohort[i])) {
                revert AddressNotInCouncil(owners, dp.secondCohort[i]);
            }
        }

        DeployedContracts memory deployedContracts;

        // deploy nominee election governor
        deployedContracts.nomineeElectionGovernor = SecurityCouncilNomineeElectionGovernor(
            payable(_deployProxy(dp.govChainProxyAdmin, impls.nomineeElectionGovernor, ""))
        );

        // deploy member election governor
        deployedContracts.memberElectionGovernor = SecurityCouncilMemberElectionGovernor(
            payable(_deployProxy(dp.govChainProxyAdmin, impls.memberElectionGovernor, ""))
        );

        // deploy security council manager
        deployedContracts.securityCouncilManager = SecurityCouncilManager(
            _deployProxy(dp.govChainProxyAdmin, impls.securityCouncilManager, "")
        );

        // deploy security council member remover gov
        deployedContracts.securityCouncilMemberRemoverGov = SecurityCouncilMemberRemovalGovernor(
            payable(_deployProxy(dp.govChainProxyAdmin, impls.securityCouncilMemberRemoverGov, ""))
        );

        // create council manager roles
        address[] memory memberRemovers = new address[](2);
        memberRemovers[0] = address(deployedContracts.securityCouncilMemberRemoverGov);
        memberRemovers[1] = dp.govChainEmergencySecurityCouncil;
        SecurityCouncilManagerRoles memory roles = SecurityCouncilManagerRoles({
            admin: dp.l2UpgradeExecutor,
            cohortUpdator: address(deployedContracts.memberElectionGovernor),
            memberAdder: dp.govChainEmergencySecurityCouncil,
            memberRemovers: memberRemovers,
            memberRotator: dp.govChainEmergencySecurityCouncil,
            memberReplacer: dp.govChainEmergencySecurityCouncil
        });

        deployedContracts.upgradeExecRouteBuilder = new UpgradeExecRouteBuilder({
            _upgradeExecutors: dp.upgradeExecutors,
            _l1ArbitrumTimelock: dp.l1ArbitrumTimelock,
            _l1TimelockMinDelay: dp.l1TimelockMinDelay
        });

        // init the deployed contracts
        _initElectionGovernors(
            dp,
            deployedContracts.securityCouncilManager,
            deployedContracts.nomineeElectionGovernor,
            deployedContracts.memberElectionGovernor
        );

        deployedContracts.securityCouncilManager.initialize({
            _firstCohort: dp.firstCohort,
            _secondCohort: dp.secondCohort,
            _securityCouncils: dp.securityCouncils,
            _roles: roles,
            _l2CoreGovTimelock: payable(dp.l2CoreGovTimelock),
            _router: deployedContracts.upgradeExecRouteBuilder
        });

        _initRemovalGov(
            dp,
            deployedContracts.securityCouncilManager,
            deployedContracts.securityCouncilMemberRemoverGov
        );

        emit ContractsDeployed(deployedContracts);
        return deployedContracts;
    }

    /// @dev initializes the removal governor
    function _initRemovalGov(
        DeployParams memory dp,
        ISecurityCouncilManager _securityCouncilManager,
        SecurityCouncilMemberRemovalGovernor securityCouncilMemberRemoverGov
    ) internal {
        securityCouncilMemberRemoverGov.initialize({
            _securityCouncilManager: _securityCouncilManager,
            _voteSuccessNumerator: dp.removalGovVoteSuccessNumerator,
            _token: IVotesUpgradeable(dp.arbToken),
            _owner: dp.l2UpgradeExecutor,
            _votingDelay: dp.removalGovVotingDelay,
            _votingPeriod: dp.removalGovVotingPeriod,
            _quorumNumerator: dp.removalGovQuorumNumerator,
            _proposalThreshold: dp.removalGovProposalThreshold,
            _minPeriodAfterQuorum: dp.removalGovMinPeriodAfterQuorum,
            _proposalExpirationBlocks: dp.removalProposalExpirationBlocks
        });
    }

    /// @dev initializes the election governors
    function _initElectionGovernors(
        DeployParams memory dp,
        ISecurityCouncilManager securityCouncilManager,
        SecurityCouncilNomineeElectionGovernor nomineeElectionGovernor,
        SecurityCouncilMemberElectionGovernor memberElectionGovernor
    ) internal {
        nomineeElectionGovernor.initialize(
            SecurityCouncilNomineeElectionGovernor.InitParams({
                firstNominationStartDate: dp.firstNominationStartDate,
                nomineeVettingDuration: dp.nomineeVettingDuration,
                nomineeVetter: dp.nomineeVetter,
                securityCouncilManager: securityCouncilManager,
                securityCouncilMemberElectionGovernor: memberElectionGovernor,
                token: IVotesUpgradeable(dp.arbToken),
                owner: dp.l2UpgradeExecutor,
                quorumNumeratorValue: dp.nomineeQuorumNumerator,
                votingPeriod: dp.nomineeVotingPeriod
            })
        );

        memberElectionGovernor.initialize({
            _nomineeElectionGovernor: nomineeElectionGovernor,
            _securityCouncilManager: securityCouncilManager,
            _token: IVotesUpgradeable(dp.arbToken),
            _owner: dp.l2UpgradeExecutor,
            _votingPeriod: dp.memberVotingPeriod,
            _fullWeightDuration: dp.fullWeightDuration
        });
    }
}
