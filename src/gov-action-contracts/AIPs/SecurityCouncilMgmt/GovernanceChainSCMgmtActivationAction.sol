// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../../security-council-mgmt/interfaces/IGnosisSafe.sol";
import "../../address-registries/L2AddressRegistryInterfaces.sol";
import "./SecurityCouncilMgmtUpgradeLib.sol";
import "../../../interfaces/IArbitrumDAOConstitution.sol";
import "../../../interfaces/IUpgradeExecutor.sol";
import "../../../interfaces/ICoreTimelock.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract GovernanceChainSCMgmtActivationAction {
    IGnosisSafe public immutable newEmergencySecurityCouncil;
    IGnosisSafe public immutable newNonEmergencySecurityCouncil;

    IGnosisSafe public immutable prevEmergencySecurityCouncil;
    IGnosisSafe public immutable prevNonEmergencySecurityCouncil;

    uint256 public immutable emergencySecurityCouncilThreshold;
    uint256 public immutable nonEmergencySecurityCouncilThreshold;

    address public immutable securityCouncilManager;
    IL2AddressRegistry public immutable l2AddressRegistry;

    constructor(
        IGnosisSafe _newEmergencySecurityCouncil,
        IGnosisSafe _newNonEmergencySecurityCouncil,
        IGnosisSafe _prevEmergencySecurityCouncil,
        IGnosisSafe _prevNonEmergencySecurityCouncil,
        uint256 _emergencySecurityCouncilThreshold,
        uint256 _nonEmergencySecurityCouncilThreshold,
        address _securityCouncilManager,
        IL2AddressRegistry _l2AddressRegistry
    ) {
        newEmergencySecurityCouncil = _newEmergencySecurityCouncil;
        newNonEmergencySecurityCouncil = _newNonEmergencySecurityCouncil;

        prevEmergencySecurityCouncil = _prevEmergencySecurityCouncil;
        prevNonEmergencySecurityCouncil = _prevNonEmergencySecurityCouncil;

        emergencySecurityCouncilThreshold = _emergencySecurityCouncilThreshold;
        nonEmergencySecurityCouncilThreshold = _nonEmergencySecurityCouncilThreshold;

        securityCouncilManager = _securityCouncilManager;
        l2AddressRegistry = _l2AddressRegistry;
    }

    function perform() external {
        IUpgradeExecutor upgradeExecutor = IUpgradeExecutor(l2AddressRegistry.coreGov().owner());

        // swap in new emergency security council
        SecurityCouncilMgmtUpgradeLib.replaceEmergencySecurityCouncil({
            _prevSecurityCouncil: prevEmergencySecurityCouncil,
            _newSecurityCouncil: newEmergencySecurityCouncil,
            _threshold: emergencySecurityCouncilThreshold,
            _upgradeExecutor: upgradeExecutor
        });

        // swap in new nonEmergency security council
        SecurityCouncilMgmtUpgradeLib.requireSafesEquivalent(
            prevNonEmergencySecurityCouncil,
            newNonEmergencySecurityCouncil,
            nonEmergencySecurityCouncilThreshold
        );

        ICoreTimelock l2CoreGovTimelock =
            ICoreTimelock(address(l2AddressRegistry.coreGovTimelock()));

        bytes32 TIMELOCK_PROPOSAL_ROLE = l2CoreGovTimelock.PROPOSER_ROLE();
        bytes32 TIMELOCK_CANCELLER_ROLE = l2CoreGovTimelock.CANCELLER_ROLE();

        // switch proposal role from old to new nonemergency council
        require(
            l2CoreGovTimelock.hasRole(
                TIMELOCK_PROPOSAL_ROLE, address(prevNonEmergencySecurityCouncil)
            ),
            "GovernanceChainSCMgmtActivationAction: prev nonemergency council doesn't have proposal role"
        );
        require(
            !l2CoreGovTimelock.hasRole(
                TIMELOCK_PROPOSAL_ROLE, address(newNonEmergencySecurityCouncil)
            ),
            "GovernanceChainSCMgmtActivationAction: new nonemergency council already has proposal role"
        );

        l2CoreGovTimelock.revokeRole(
            TIMELOCK_PROPOSAL_ROLE, address(prevNonEmergencySecurityCouncil)
        );

        l2CoreGovTimelock.grantRole(TIMELOCK_PROPOSAL_ROLE, address(newNonEmergencySecurityCouncil));

        // give timelock access to manager
        require(
            Address.isContract(securityCouncilManager),
            "GovernanceChainSCMgmtActivationAction: manager address isn't a contract"
        );

        require(
            !l2CoreGovTimelock.hasRole(TIMELOCK_PROPOSAL_ROLE, securityCouncilManager),
            "GovernanceChainSCMgmtActivationAction: securityCouncilManager already has proposal role"
        );
        l2CoreGovTimelock.grantRole(TIMELOCK_PROPOSAL_ROLE, securityCouncilManager);

        // switch cancellor role from old to new emergency council
        require(
            l2CoreGovTimelock.hasRole(
                TIMELOCK_CANCELLER_ROLE, address(prevEmergencySecurityCouncil)
            ),
            "GovernanceChainSCMgmtActivationAction: prev emergency security council should have cancellor role"
        );
        require(
            !l2CoreGovTimelock.hasRole(
                TIMELOCK_CANCELLER_ROLE, address(newEmergencySecurityCouncil)
            ),
            "GovernanceChainSCMgmtActivationAction: new emergency security council already has cancellor role"
        );

        l2CoreGovTimelock.revokeRole(TIMELOCK_CANCELLER_ROLE, address(prevEmergencySecurityCouncil));
        l2CoreGovTimelock.grantRole(TIMELOCK_CANCELLER_ROLE, address(newEmergencySecurityCouncil));

        // confirm updates
        bytes32 EXECUTOR_ROLE = upgradeExecutor.EXECUTOR_ROLE();
        require(
            upgradeExecutor.hasRole(EXECUTOR_ROLE, address(newEmergencySecurityCouncil)),
            "NonGovernanceChainSCMgmtActivationAction: new emergency security council not set"
        );
        require(
            !upgradeExecutor.hasRole(EXECUTOR_ROLE, address(prevEmergencySecurityCouncil)),
            "NonGovernanceChainSCMgmtActivationAction: prev emergency security council still set"
        );

        require(
            !l2CoreGovTimelock.hasRole(
                TIMELOCK_PROPOSAL_ROLE, address(prevNonEmergencySecurityCouncil)
            ),
            "GovernanceChainSCMgmtActivationAction: prev nonemergency council still has proposal role"
        );
        require(
            l2CoreGovTimelock.hasRole(
                TIMELOCK_PROPOSAL_ROLE, address(newNonEmergencySecurityCouncil)
            ),
            "GovernanceChainSCMgmtActivationAction: new nonemergency doesn't have proposal role"
        );

        require(
            l2CoreGovTimelock.hasRole(TIMELOCK_PROPOSAL_ROLE, securityCouncilManager),
            "GovernanceChainSCMgmtActivationAction: securityCouncilManager doesn't have proposal role"
        );
        
        require(
            !l2CoreGovTimelock.hasRole(
                TIMELOCK_CANCELLER_ROLE, address(prevEmergencySecurityCouncil)
            ),
            "GovernanceChainSCMgmtActivationAction: prev emergency security council still has cancellor role"
        );
        require(
            l2CoreGovTimelock.hasRole(
                TIMELOCK_CANCELLER_ROLE, address(newEmergencySecurityCouncil)
            ),
            "GovernanceChainSCMgmtActivationAction: new emergency security council doesn't have cancellor role"
        );
    }
}
