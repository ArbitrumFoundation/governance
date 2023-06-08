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

/// @notice Factory contract for deploying and initializing L1 Security Council contracts: l1SecurityCouncilUpdateRouter and l1SecurityCouncilUpgradeExecutor
/// Has a layer 2 dependency, so deployment takes 2 steps
contract L1SecurityCouncilMgmtFactory is Ownable {
    IL1SecurityCouncilUpdateRouter public l1SecurityCouncilUpdateRouter;
    address public l1SecurityCouncilUpgradeExecutor;

    event ContractsDeployed(
        address l1SecurityCouncilUpgradeExecutor, address l1SecurityCouncilUpdateRouter
    );
    event UpdateRouterInitialized();

    enum Step {
        One,
        Three,
        Complete
    }

    Step public step = Step.One;
    /// @notice Step One: Deploy L1SecurityCouncilUpgradeExecutor and L1SecurityCouncilUpdateRouter
    /// @param _proxyAdmin address of the proxy admin of L1 governance contracts
    /// @param _l1UpgradeExecutor address of DAO's L1 updrade executor
    /// @param _l1SecurityCouncil address of the L1 emergency Security Council

    function deployStep1(
        address _proxyAdmin,
        address _l1UpgradeExecutor,
        address _l1SecurityCouncil
    ) external onlyOwner {
        require(step == Step.One, "L1SecurityCouncilMgmtFactory: step is not One");
        require(
            Address.isContract(_proxyAdmin),
            "L1SecurityCouncilMgmtFactory: _proxyAdmin is not a contract"
        );
        require(
            Address.isContract(_l1SecurityCouncil),
            "L1SecurityCouncilMgmtFactory: _l1SecurityCouncil is not a contract"
        );

        // Deploy L1 Security Council Update Router
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

        // deploy L1 Security Council Upgrade Exectutior
        SecurityCouncilUpgradeExecutorFactory securityCouncilUpgradeExecutorFactory =
            new SecurityCouncilUpgradeExecutorFactory();
        address _l1SecurityCouncilUpgradeExecutor = securityCouncilUpgradeExecutorFactory.deploy({
            securityCouncil: IGnosisSafe(_l1SecurityCouncil),
            securityCouncilUpdator: address(l1SecurityCouncilUpdateRouter), // Router is owner (can update members)
            proxyAdmin: _proxyAdmin,
            upgradeExecutorAdmin: _l1UpgradeExecutor
        });
        // save l1SecurityCouncilUpgradeExecutor for deploy step3
        l1SecurityCouncilUpgradeExecutor = _l1SecurityCouncilUpgradeExecutor;

        // update to step 3
        step = Step.Three;
        emit ContractsDeployed(
            address(l1SecurityCouncilUpgradeExecutor), address(l1SecurityCouncilUpdateRouter)
        );
    }
    /// @notice Step Three: initialize L1SecurityCouncilUpdateRouter
    /// @param _governanceChainInbox L1 address of the inbox of the Arbitrum chain that handles governance
    /// @param _l2SecurityCouncilManager L2 address of the Security Council Manager on the governance chain
    /// @param _l1UpgradeExecutor L1 address of the Uprade Executor (DAO)

    function deployStep3(
        address _governanceChainInbox,
        address _l2SecurityCouncilManager,
        address _l1UpgradeExecutor,
        L2ChainToUpdate[] memory _initiall2ChainsToUpdateArr
    ) external onlyOwner {
        require(step == Step.Three, "L1SecurityCouncilMgmtFactory: step is not Three");
        // initialize l1SecurityCouncilUpdateRouter
        l1SecurityCouncilUpdateRouter.initialize({
            _governanceChainInbox: _governanceChainInbox,
            _l1SecurityCouncilUpgradeExecutor: l1SecurityCouncilUpgradeExecutor,
            _l2SecurityCouncilManager: _l2SecurityCouncilManager,
            _initiall2ChainsToUpdateArr: _initiall2ChainsToUpdateArr,
            _owner: _l1UpgradeExecutor
        });
        step = Step.Complete;
        emit UpdateRouterInitialized();
    }
}
