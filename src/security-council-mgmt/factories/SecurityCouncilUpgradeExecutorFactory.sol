// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IGnosisSafe.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../SecurityCouncilUpgradeExecutor.sol";

contract SecurityCouncilUpgradeExecutorFactory is Ownable {
    event SecurityCouncilUpgradeExecutorCreated(address indexed securityCouncilUpgradeExecutor);

    function delpoy(IGnosisSafe securityCouncil, address securityCouncilOwner, address proxyAdmin)
        external
        onlyOwner
        returns (address securityCouncilUpradeExecutorAddress)
    {
        require(
            Address.isContract(address(securityCouncil)),
            "SecurityCouncilUpgradeExecutorFactory: securityCouncil is not a contract"
        );
        require(
            Address.isContract(proxyAdmin),
            "SecurityCouncilUpgradeExecutorFactory: proxyAdmin is not a contract"
        );
        require(
            securityCouncilOwner != address(0),
            "SecurityCouncilUpgradeExecutorFactory: securityCouncilOwner is zero address"
        );

        SecurityCouncilUpgradeExecutor securityCouncilUpgradeExecutorLogic = new SecurityCouncilUpgradeExecutor();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(securityCouncilUpgradeExecutorLogic),
            proxyAdmin,
            bytes("")
        );
        SecurityCouncilUpgradeExecutor securityCouncilUpgradeExecutor = SecurityCouncilUpgradeExecutor(address(proxy));
        securityCouncilUpgradeExecutor.initialize(securityCouncil, securityCouncilOwner);

        emit SecurityCouncilUpgradeExecutorCreated(address(securityCouncilUpgradeExecutor));
        return address(securityCouncilUpgradeExecutor);
    }
}