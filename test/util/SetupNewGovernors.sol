// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {TimelockControllerUpgradeable} from
    "openzeppelin-upgradeable-v5/governance/TimelockControllerUpgradeable.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable-v5/governance/GovernorUpgradeable.sol";
import {SubmitUpgradeProposalScript} from "script/SubmitUpgradeProposalScript.s.sol";
import {BaseGovernorDeployer} from "script/BaseGovernorDeployer.sol";
import {DeployImplementation} from "script/DeployImplementation.s.sol";
import {DeployCoreGovernor} from "script/DeployCoreGovernor.s.sol";
import {DeployTreasuryGovernor} from "script/DeployTreasuryGovernor.s.sol";
import {DeployTimelockRolesUpgrader} from "script/DeployTimelockRolesUpgrader.s.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";
import {L2ArbitrumGovernorV2} from "src/L2ArbitrumGovernorV2.sol";
import {TimelockRolesUpgrader} from
    "src/gov-action-contracts/gov-upgrade-contracts/update-timelock-roles/TimelockRolesUpgrader.sol";

abstract contract SetupNewGovernors is SharedGovernorConstants, Test {
    // Deploy & setup scripts
    SubmitUpgradeProposalScript submitUpgradeProposalScript;
    TimelockRolesUpgrader timelockRolesUpgrader;
    BaseGovernorDeployer proxyCoreGovernorDeployer;
    BaseGovernorDeployer proxyTreasuryGovernorDeployer;

    // Current governors and timelocks
    GovernorUpgradeable currentCoreGovernor;
    TimelockControllerUpgradeable currentCoreTimelock;
    GovernorUpgradeable currentTreasuryGovernor;
    TimelockControllerUpgradeable currentTreasuryTimelock;

    // New governors
    L2ArbitrumGovernorV2 newCoreGovernor;
    L2ArbitrumGovernorV2 newTreasuryGovernor;

    function setUp() public virtual {
        vm.createSelectFork(
            vm.envOr(
                "ARBITRUM_ONE_RPC_URL", string("Please set ARBITRUM_ONE_RPC_URL in your .env file")
            ),
            FORK_BLOCK
        );

        // Deploy Governor implementation contract
        DeployImplementation _implementationDeployer = new DeployImplementation();
        _implementationDeployer.setUp();
        address _implementation = address(_implementationDeployer.run());

        proxyCoreGovernorDeployer = new DeployCoreGovernor();
        proxyTreasuryGovernorDeployer = new DeployTreasuryGovernor();
        proxyCoreGovernorDeployer.setUp();
        proxyTreasuryGovernorDeployer.setUp();

        // Deploy Governor proxy contracts
        newCoreGovernor = L2_CORE_GOVERNOR_NEW_DEPLOY == address(0)
            ? proxyCoreGovernorDeployer.run(_implementation)
            : L2ArbitrumGovernorV2(payable(L2_CORE_GOVERNOR_NEW_DEPLOY));
        newTreasuryGovernor = L2_TREASURY_GOVERNOR_NEW_DEPLOY == address(0)
            ? proxyTreasuryGovernorDeployer.run(_implementation)
            : L2ArbitrumGovernorV2(payable(L2_TREASURY_GOVERNOR_NEW_DEPLOY));

        // Current governors and timelocks
        currentCoreGovernor = GovernorUpgradeable(payable(L2_CORE_GOVERNOR));
        currentCoreTimelock = TimelockControllerUpgradeable(payable(L2_CORE_GOVERNOR_TIMELOCK));
        currentTreasuryGovernor = GovernorUpgradeable(payable(L2_TREASURY_GOVERNOR));
        currentTreasuryTimelock =
            TimelockControllerUpgradeable(payable(L2_TREASURY_GOVERNOR_TIMELOCK));

        // Deploy a mock ArbSys contract at L2_ARB_SYS
        vm.allowCheatcodes(address(L2_ARB_SYS));
        MockArbSys mockArbSys = new MockArbSys();
        bytes memory code = address(mockArbSys).code;
        vm.etch(L2_ARB_SYS, code);

        // Prepare the script to submit upgrade proposal
        submitUpgradeProposalScript = new SubmitUpgradeProposalScript();
        DeployTimelockRolesUpgrader deployTimelockRolesUpgrader = new DeployTimelockRolesUpgrader();
        timelockRolesUpgrader = deployTimelockRolesUpgrader.run();
    }
}

/// @dev Here we mock ArbSys, the contract that the timelock uses to make an L2 to L1 call. Normal call flow would
/// then see the call flow to ArbOne Outbox, to L1 timelock, to L1 ArbOne Inbox, to L2 Retryable buffer, to L2 Upgrade
/// Executor. Here, we assume this L1 call flow occurs. We make loose assertions about what calldata at each of these
/// steps looks like, and we finally arrive at the decoded calldata to pass to Upgrade Executor. Everything from ArbSys
/// to UpgradeExecutor is "fake" here, while preserving some loose confidence.
contract MockArbSys is SharedGovernorConstants, Test {
    function sendTxToL1(address _l1Target, bytes calldata _data) external {
        (
            address _retryableTicketMagic,
            /*uint256 _ignored*/
            ,
            bytes memory _retryableData,
            /*bytes32 _predecessor*/
            ,
            /*bytes32 _description*/
            ,
            /*uint256 _minDelay*/
        ) = abi.decode(_data[4:], (address, uint256, bytes, bytes32, bytes32, uint256));

        assertEq(_l1Target, L1_TIMELOCK);
        assertEq(_retryableTicketMagic, RETRYABLE_TICKET_MAGIC);

        (
            address _arbOneDelayedInbox,
            address _upgradeExecutor,
            /*uint256 _value*/
            ,
            /*uint256 _maxGas*/
            ,
            /*uint256 _maxFeePerGas*/
            ,
            bytes memory _upgradeExecutorCallData
        ) = abi.decode(_retryableData, (address, address, uint256, uint256, uint256, bytes));

        assertEq(_arbOneDelayedInbox, L1_ARB_ONE_DELAYED_INBOX);
        assertEq(_upgradeExecutor, L2_UPGRADE_EXECUTOR);

        vm.prank(L2_SECURITY_COUNCIL_9);
        (bool success, /*bytes memory data*/ ) = _upgradeExecutor.call(_upgradeExecutorCallData);
        assertEq(success, true);
    }
}

interface IUpgradeExecutor {
    function execute(address to, bytes calldata data) external payable;
}
