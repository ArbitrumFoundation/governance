// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./SecurityCouncilUpgradeExecutorFactory.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "./SecurityCouncilUpgradeExecutorFactory.sol";
import "../interfaces/IGnosisSafe.sol";
import "../interfaces/IL1SecurityCouncilUpdateRouter.sol";

import "@openzeppelin/contracts/utils/Address.sol";
import "../L1SecurityCouncilUpdateRouter.sol";

/**
 * @title L1SecurityCouncilMgmtFactory
 * @notice Factory for deploying L1SecurityCouncilMgmt contracts.
 */

contract L1SecurityCouncilMgmtFactory is Ownable {
    address public l1UpgradeExecutor;
    IL1SecurityCouncilUpdateRouter public l1SecurityCouncilUpdateRouter;
    address public l1SecurityCouncilUpgradeExecutor;

    enum Step {
        One,
        Three,
        Complete
    }

    Step public step = Step.One;

    function deployStep1(
        address _proxyAdmin,
        address _l1SecurityCouncil,
        address _l1UpgradeExecutor
    ) external onlyOwner {
        require(step == Step.One, "L1SecurityCouncilMgmtFactory: step is not One");
        // address checks
        require(
            Address.isContract(_proxyAdmin),
            "L1SecurityCouncilMgmtFactory: _proxyAdmin is not a contract"
        );
        require(
            Address.isContract(_l1SecurityCouncil),
            "L1SecurityCouncilMgmtFactory: _l1SecurityCouncil is not a contract"
        );
        require(
            Address.isContract(_l1UpgradeExecutor),
            "L1SecurityCouncilMgmtFactory: _l1UpgradeExecutor is not a contract"
        );
        l1UpgradeExecutor = _l1UpgradeExecutor;

        SecurityCouncilUpgradeExecutorFactory securityCouncilUpgradeExecutorFactory =
            new SecurityCouncilUpgradeExecutorFactory();
        address _l1SecurityCouncilUpgradeExecutor = securityCouncilUpgradeExecutorFactory.deploy({
            securityCouncil: IGnosisSafe(_l1SecurityCouncil),
            securityCouncilOwner: _l1UpgradeExecutor,
            proxyAdmin: _proxyAdmin
        });
        l1SecurityCouncilUpgradeExecutor = _l1SecurityCouncilUpgradeExecutor;

        L1SecurityCouncilUpdateRouter l1SecurityCouncilUpdateRouterLogic =
            new L1SecurityCouncilUpdateRouter();

        TransparentUpgradeableProxy l1SecurityCouncilUpdateRouterProxy =
        new TransparentUpgradeableProxy(
            address(l1SecurityCouncilUpdateRouterLogic),
            _proxyAdmin,
            bytes("")
        );
        IL1SecurityCouncilUpdateRouter l1SecurityCouncilUpdateRouter =
            IL1SecurityCouncilUpdateRouter(address(l1SecurityCouncilUpdateRouterProxy));

        // event
        step = Step.Three;
    }

    function deployStep3(address _governanceChainInbox, address _l2SecurityCouncilManager)
        external
        onlyOwner
    {
        require(step == Step.Three, "L1SecurityCouncilMgmtFactory: step is not Three");
    }
}
