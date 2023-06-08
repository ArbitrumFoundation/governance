// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IGnosisSafe.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../SecurityCouncilUpgradeExecutor.sol";

/// @notice Factory for deploying SecurityCouncilUpgradeExecutor contract for a given securiy council
contract SecurityCouncilUpgradeExecutorFactory is Ownable {
    event SecurityCouncilUpgradeExecutorCreated(address indexed securityCouncilUpgradeExecutor);

    /// @notice Deploys SecurityCouncilUpgradeExecutor contract for a given securiy council
    /// @param securityCouncil Security council contract address
    /// @param securityCouncilUpdator Security council updatr address, which has affordance to update members
    /// @param proxyAdmin Address for governance contract proxy admin for the target security council's chain
    function deploy(
        IGnosisSafe securityCouncil,
        address securityCouncilUpdator,
        address upgradeExecutorAdmin,
        address proxyAdmin
    ) external onlyOwner returns (address securityCouncilUpradeExecutorAddress) {
        require(
            Address.isContract(address(securityCouncil)),
            "SecurityCouncilUpgradeExecutorFactory: securityCouncil is not a contract"
        );
        require(
            Address.isContract(proxyAdmin),
            "SecurityCouncilUpgradeExecutorFactory: proxyAdmin is not a contract"
        );
        require(
            securityCouncilUpdator != address(0),
            "SecurityCouncilUpgradeExecutorFactory: securityCouncilUpdator is zero address"
        );
        require(
            upgradeExecutorAdmin != address(0),
            "SecurityCouncilUpgradeExecutorFactory: upgradeExecutorAdmin is zero address"
        );

        SecurityCouncilUpgradeExecutor securityCouncilUpgradeExecutorLogic =
            new SecurityCouncilUpgradeExecutor();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(securityCouncilUpgradeExecutorLogic),
            proxyAdmin,
            bytes("")
        );
        SecurityCouncilUpgradeExecutor securityCouncilUpgradeExecutor =
            SecurityCouncilUpgradeExecutor(address(proxy));
        securityCouncilUpgradeExecutor.initialize(
            securityCouncil, securityCouncilUpdator, upgradeExecutorAdmin
        );

        emit SecurityCouncilUpgradeExecutorCreated(address(securityCouncilUpgradeExecutor));
        return address(securityCouncilUpgradeExecutor);
    }
}
