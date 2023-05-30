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

contract L2SecurityCouncilMgmtFactory is Ownable {
    function deployStep2(
        address _govChainEmergencySecurityCouncil,
        address _govChainNonEmergencySecurityCouncil,
        address _l1SecurityCouncilUpdateRouter,
        address _proxyAdmin,
        address[] memory _marchCohort,
        address[] memory _septemberCohort,
        address l2UpgradeExecutor
    ) external onlyOwner {
        // todo address checks
        SecurityCouncilUpgradeExecutorFactory securityCouncilUpgradeExecutorFactory =
            new SecurityCouncilUpgradeExecutorFactory();

        address l2EmergencySecurityCouncilUpgradeExecutor = securityCouncilUpgradeExecutorFactory
            .deploy({
            securityCouncil: IGnosisSafe(_govChainEmergencySecurityCouncil),
            securityCouncilOwner: AddressAliasHelper.applyL1ToL2Alias(_l1SecurityCouncilUpdateRouter),
            proxyAdmin: _proxyAdmin
        });

        address l2NonEmergencySecurityCouncilUpgradeExecutor = securityCouncilUpgradeExecutorFactory
            .deploy({
            securityCouncil: IGnosisSafe(_govChainNonEmergencySecurityCouncil),
            securityCouncilOwner: AddressAliasHelper.applyL1ToL2Alias(_l1SecurityCouncilUpdateRouter),
            proxyAdmin: _proxyAdmin
        });

        // removal gov
        SecurityCouncilMemberRemoverGov securityCouncilMemberRemoverGovLogic =
            new SecurityCouncilMemberRemoverGov();

        SecurityCouncilManager securityCouncilManagerLogic = new SecurityCouncilManager();

        Roles memory roles = Roles({
            admin: l2UpgradeExecutor,
            cohortUpdator: _govChainEmergencySecurityCouncil,
            memberAdder: _govChainEmergencySecurityCouncil,
            memberRemover: address(securityCouncilMemberRemoverGovLogic)
        });

        TargetContracts memory targetContracts = TargetContracts({
            govChainEmergencySecurityCouncilUpgradeExecutor: l2EmergencySecurityCouncilUpgradeExecutor,
            govChainNonEmergencySecurityCouncilUpgradeExecutor: l2NonEmergencySecurityCouncilUpgradeExecutor,
            l1SecurityCouncilUpdateRouter: _l1SecurityCouncilUpdateRouter
        });

        TransparentUpgradeableProxy securityCouncilManagerProxy = new TransparentUpgradeableProxy(
            address(securityCouncilManagerLogic),
            _proxyAdmin,
            bytes("")
        );
        ISecurityCouncilManager securityCouncilManager =
            ISecurityCouncilManager(address(securityCouncilManagerProxy));

        securityCouncilManager.initialize(_marchCohort, _septemberCohort, roles, targetContracts);
    }
}
