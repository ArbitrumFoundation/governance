// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import {Test, console2} from "forge-std/Test.sol";
import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {
    GovernorUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {SubmitUpgradeProposalScript} from "scripts/forge-scripts/SubmitUpgradeProposalScript.s.sol";
import {DeployImplementation} from "scripts/forge-scripts/DeployImplementation.s.sol";
import {
    DeployMultiProxyUpgradeAction
} from "scripts/forge-scripts/DeployMultiProxyUpgradeAction.s.sol";
import {DeployConstants} from "scripts/forge-scripts/DeployConstants.sol";
import {L2ArbitrumGovernorV2} from "src/L2ArbitrumGovernorV2.sol";
import {L2ArbitrumGovernor} from "src/L2ArbitrumGovernor.sol";
import {
    MultiProxyUpgradeAction
} from "src/gov-action-contracts/gov-upgrade-contracts/upgrade-proxy/MultiProxyUpgradeAction.sol";

abstract contract SetupNewGovernors is DeployConstants, Test {
    // Deploy & setup scripts
    SubmitUpgradeProposalScript submitUpgradeProposalScript;
    MultiProxyUpgradeAction multiProxyUpgradeAction;

    // Current governors and timelocks
    L2ArbitrumGovernor currentCoreGovernor;
    TimelockControllerUpgradeable currentCoreTimelock;
    L2ArbitrumGovernor currentTreasuryGovernor;
    TimelockControllerUpgradeable currentTreasuryTimelock;

    // New governors
    L2ArbitrumGovernorV2 newGovernorImplementation;

    uint256 constant FORK_BLOCK = 245_608_716; // Arbitrary recent block

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }
    enum VoteType {
        Against,
        For,
        Abstain
    }

    function setUp() public virtual {
        vm.createSelectFork(
            vm.envOr(
                "ARBITRUM_ONE_RPC_URL", string("Please set ARBITRUM_ONE_RPC_URL in your .env file")
            ),
            FORK_BLOCK
        );

        // Deploy Governor implementation contract
        DeployImplementation _implementationDeployer = new DeployImplementation();
        address _implementation = address(_implementationDeployer.run());

        // Deploy Governor proxy contracts
        newGovernorImplementation = L2_ARBITRUM_GOVERNOR_V2_IMPLEMENTATION == address(0)
            ? L2ArbitrumGovernorV2(payable(_implementation))
            : L2ArbitrumGovernorV2(payable(L2_ARBITRUM_GOVERNOR_V2_IMPLEMENTATION));

        // Current governors and timelocks
        currentCoreGovernor = L2ArbitrumGovernor(payable(L2_CORE_GOVERNOR));
        currentCoreTimelock = TimelockControllerUpgradeable(payable(L2_CORE_GOVERNOR_TIMELOCK));
        currentTreasuryGovernor = L2ArbitrumGovernor(payable(L2_TREASURY_GOVERNOR));
        currentTreasuryTimelock =
            TimelockControllerUpgradeable(payable(L2_TREASURY_GOVERNOR_TIMELOCK));

        // Deploy a mock ArbSys contract at L2_ARB_SYS
        vm.allowCheatcodes(address(L2_ARB_SYS));
        MockArbSys mockArbSys = new MockArbSys();
        bytes memory code = address(mockArbSys).code;
        vm.etch(L2_ARB_SYS, code);

        // Prepare the script to submit upgrade proposal
        submitUpgradeProposalScript = new SubmitUpgradeProposalScript();
        DeployMultiProxyUpgradeAction deployMultiProxyUpgradeAction =
            new DeployMultiProxyUpgradeAction();
        multiProxyUpgradeAction =
            deployMultiProxyUpgradeAction.run(address(newGovernorImplementation));
    }
}

/// @dev Here we mock ArbSys, the contract that the timelock uses to make an L2 to L1 call. Normal call flow would
/// then see the call flow to ArbOne Outbox, to L1 timelock, to L1 ArbOne Inbox, to L2 Retryable buffer, to L2 Upgrade
/// Executor. Here, we assume this L1 call flow occurs. We make loose assertions about what calldata at each of these
/// steps looks like, and we finally arrive at the decoded calldata to pass to Upgrade Executor. Everything from ArbSys
/// to UpgradeExecutor is "fake" here, while preserving some loose confidence.
contract MockArbSys is DeployConstants, Test {
    function sendTxToL1(address _l1Target, bytes calldata _data) external {
        (
            address _retryableTicketMagic,
            /*uint256 _ignored*/,
            bytes memory _retryableData,
            /*bytes32 _predecessor*/,
            /*bytes32 _description*/,
            /*uint256 _minDelay*/
        ) = abi.decode(_data[4:], (address, uint256, bytes, bytes32, bytes32, uint256));

        assertEq(_l1Target, L1_TIMELOCK);
        assertEq(_retryableTicketMagic, L2_RETRYABLE_TICKET_MAGIC);

        (
            address _arbOneDelayedInbox,
            address _upgradeExecutor,
            /*uint256 _value*/,
            /*uint256 _maxGas*/,
            /*uint256 _maxFeePerGas*/,
            bytes memory _upgradeExecutorCallData
        ) = abi.decode(_retryableData, (address, address, uint256, uint256, uint256, bytes));

        assertEq(_arbOneDelayedInbox, L1_ARB_ONE_DELAYED_INBOX);
        assertEq(_upgradeExecutor, L2_UPGRADE_EXECUTOR);

        vm.prank(L2_SECURITY_COUNCIL_9);
        (
            bool success, /*bytes memory data*/
        ) = _upgradeExecutor.call(_upgradeExecutorCallData);
        assertEq(success, true);
    }
}

interface IUpgradeExecutor {
    function execute(address to, bytes calldata data) external payable;
}
