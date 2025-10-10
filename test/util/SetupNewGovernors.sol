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
    address[] public _majorDelegates;

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

        // Set the major delegates for testing
        _majorDelegates = new address[](18);
        _majorDelegates[0] = 0x1B686eE8E31c5959D9F5BBd8122a58682788eeaD; // L2BEAT
        _majorDelegates[1] = 0xF4B0556B9B6F53E00A1FDD2b0478Ce841991D8fA; // olimpio
        _majorDelegates[2] = 0x11cd09a0c5B1dc674615783b0772a9bFD53e3A8F; // Gauntlet
        _majorDelegates[3] = 0xB933AEe47C438f22DE0747D57fc239FE37878Dd1; // Wintermute
        _majorDelegates[4] = 0x0eB5B03c0303f2F47cD81d7BE4275AF8Ed347576; // Treasure
        _majorDelegates[5] = 0xF92F185AbD9E00F56cb11B0b709029633d1E37B4; //
        _majorDelegates[6] = 0x186e505097BFA1f3cF45c2C9D7a79dE6632C3cdc;
        _majorDelegates[7] = 0x5663D01D8109DDFC8aACf09fBE51F2d341bb3643;
        _majorDelegates[8] = 0x2ef27b114917dD53f8633440A7C0328fef132e2F; // MUX Protocol
        _majorDelegates[9] = 0xE48C655276C23F1534AE2a87A2bf8A8A6585Df70; // ercwl
        _majorDelegates[10] = 0x8A3e9846df0CDc723C06e4f0C642ffFF82b54610;
        _majorDelegates[11] = 0xAD16ebE6FfC7d96624A380F394cD64395B0C6144; // DK (Premia)
        _majorDelegates[12] = 0xA5dF0cf3F95C6cd97d998b9D990a86864095d9b0; // Blockworks Research
        _majorDelegates[13] = 0x839395e20bbB182fa440d08F850E6c7A8f6F0780; // Griff Green
        _majorDelegates[14] = 0x2e3BEf6830Ae84bb4225D318F9f61B6b88C147bF; // Camelot
        _majorDelegates[15] = 0x8F73bE66CA8c79382f72139be03746343Bf5Faa0; // mihal.eth
        _majorDelegates[16] = 0xb5B069370Ef24BC67F114e185D185063CE3479f8; // Frisson
        _majorDelegates[17] = 0xdb5781a835b60110298fF7205D8ef9678Ff1f800; // yoav.eth
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
        (bool success,/*bytes memory data*/) = _upgradeExecutor.call(_upgradeExecutorCallData);
        assertEq(success, true);
    }
}

interface IUpgradeExecutor {
    function execute(address to, bytes calldata data) external payable;
}
