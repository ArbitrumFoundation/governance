// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../address-registries/L2AddressRegistryInterfaces.sol";
import "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
import
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import "../../../security-council-mgmt/governors/SecurityCouncilNomineeElectionGovernor.sol";

/// @notice Perform the following upgrade proposed by the Arbitrum Foundation:
/// - Upgrade the sec council manager to allow member rotation and sets min rotation vars
/// - Upgrade the sec council nominee election governor to allow modifying the cadence of election
/// - Adjusting the qualification threshold of the Member Election phase from 0.2% to 0.1%
/// - Allowing existing sec council members to automatically progress from the Nominee Selection phase
/// - Updating the ArbitrumDAO Constitution to reflect these changes
contract SecurityCouncilUpgradeAction {
    IL2AddressRegistry public immutable l2AddressRegistry;
    address public immutable secCouncilManagerImpl;
    address public immutable scNomineeElectionGovernorImpl;
    uint256 public immutable minRotationPeriod;
    address public immutable minRotationPeriodSetter;
    uint256 public immutable cadenceInMonths;
    bytes32 public immutable newConstitutionHash;

    constructor(
        IL2AddressRegistry _l2AddressRegistry,
        address _secCouncilManagerImpl,
        address _scNomineeElectionGovernorImpl,
        uint256 _minRotationPeriod,
        address _minRotationPeriodSetter,
        uint256 _cadenceInMonths,
        bytes32 _newConstitutionHash
    ) {
        l2AddressRegistry = _l2AddressRegistry;
        secCouncilManagerImpl = _secCouncilManagerImpl;
        scNomineeElectionGovernorImpl = _scNomineeElectionGovernorImpl;
        minRotationPeriod = _minRotationPeriod;
        minRotationPeriodSetter = _minRotationPeriodSetter;
        cadenceInMonths = _cadenceInMonths;
        newConstitutionHash = _newConstitutionHash;
    }

    function perform() external {
        SecurityCouncilNomineeElectionGovernor scNomineeElectionGovernor =
        SecurityCouncilNomineeElectionGovernor(
            payable(address(l2AddressRegistry.scNomineeElectionGovernor()))
        );
        require(
            scNomineeElectionGovernor.electionCount() == 5,
            "SecurityCouncilUpgradeAction: not expected timing"
        );

        // Upgrade the sec council manager to allow member rotation and sets min rotation vars
        ISecurityCouncilManager secCouncilManager = l2AddressRegistry.securityCouncilManager();
        l2AddressRegistry.govProxyAdmin().upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(secCouncilManager))),
            secCouncilManagerImpl,
            abi.encodeCall(
                ISecurityCouncilManager(secCouncilManagerImpl).postUpgradeInit,
                (minRotationPeriod, minRotationPeriodSetter)
            )
        );
        require(
            minRotationPeriod == secCouncilManager.minRotationPeriod(),
            "SecurityCouncilUpgradeAction: Min rotation period not set"
        );
        require(
            IAccessControlUpgradeable(address(secCouncilManager)).hasRole(
                secCouncilManager.MIN_ROTATION_PERIOD_SETTER_ROLE(), minRotationPeriodSetter
            ),
            "SecurityCouncilUpgradeAction: Min rotation period setter not set"
        );

        // Upgrade the sec council nominee election governor to allow modifying the cadence of election
        // Allowing existing sec council members to automatically progress from the Nominee Selection phase
        l2AddressRegistry.govProxyAdmin().upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(scNomineeElectionGovernor))),
            scNomineeElectionGovernorImpl,
            abi.encodeCall(scNomineeElectionGovernor.postUpgradeInit, ())
        );

        scNomineeElectionGovernor.relay(
            address(scNomineeElectionGovernor),
            0,
            abi.encodeCall(scNomineeElectionGovernor.setCadence, (cadenceInMonths))
        );
        require(
            scNomineeElectionGovernor.cadenceInMonths() == cadenceInMonths,
            "SecurityCouncilUpgradeAction: Cadence not set"
        );

        // Adjusting the qualification threshold of the Member Election phase from 0.2% to 0.1%
        scNomineeElectionGovernor.relay(
            address(scNomineeElectionGovernor),
            0,
            abi.encodeCall(scNomineeElectionGovernor.updateQuorumNumerator, (10))
        );
        require(
            scNomineeElectionGovernor.quorumNumerator() == 10,
            "SecurityCouncilUpgradeAction: Quorum numerator not set"
        );

        // Updating the ArbitrumDAO Constitution to reflect these changes
        IArbitrumDAOConstitution arbitrumDaoConstitution =
            l2AddressRegistry.arbitrumDAOConstitution();
        arbitrumDaoConstitution.setConstitutionHash(newConstitutionHash);
        require(
            arbitrumDaoConstitution.constitutionHash() == newConstitutionHash,
            "SecurityCouncilUpgradeAction: new constitution hash not set"
        );
    }
}
