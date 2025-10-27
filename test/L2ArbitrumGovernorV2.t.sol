// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {L2ArbitrumGovernorV2} from "src/L2ArbitrumGovernorV2.sol";
import {L2ArbitrumToken} from "src/L2ArbitrumToken.sol";
import {ArbitrumTimelock} from "src/ArbitrumTimelock.sol";
import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {
    IGovernorUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {TestUtil} from "test/util/TestUtil.sol";
import {DeployConstants} from "scripts/forge-scripts/DeployConstants.sol";
import {SetupNewGovernors} from "test/util/SetupNewGovernors.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract L2ArbitrumGovernorV2Test is SetupNewGovernors {
    // Core components
    L2ArbitrumGovernorV2 internal governor;
    L2ArbitrumToken internal token;
    ArbitrumTimelock internal timelock;

    // Simple config
    address internal constant L1_TOKEN_ADDRESS = address(0x1111);
    address internal constant TOKEN_OWNER = address(0x2222);
    address internal constant OWNER = address(0x3333);

    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 internal constant VOTING_DELAY = 1;
    uint256 internal constant VOTING_PERIOD = 5;
    uint256 internal constant QUORUM_NUMERATOR = 1;
    uint256 internal constant PROPOSAL_THRESHOLD = 0; // allow proposals without voting power
    uint64 internal constant VOTE_EXTENSION = 0;

    address internal constant PROXY_ADMIN = 0xc7183455a4C133Ae270771860664b6B7ec320bB1;

    address[] internal _majorDelegates;

    // Mirror of IGovernorUpgradeable.ProposalCreated for expectEmit usage in tests
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );
    // Mirror of IGovernorTimelockUpgradeable.ProposalQueued for expectEmit usage in tests
    event ProposalQueued(uint256 proposalId, uint256 eta);
    // Mirror of IGovernorUpgradeable.ProposalExecuted for expectEmit usage in tests
    event ProposalExecuted(uint256 proposalId);

    function setUp() public virtual override {
        if (_shouldPassAndExecuteUpgradeProposal()) {
            super.setUp();
            _setMajorDelegates();
            _executeUpgradeProposal();
            governor = L2ArbitrumGovernorV2(payable(L2_CORE_GOVERNOR));
            timelock = ArbitrumTimelock(payable(L2_CORE_GOVERNOR_TIMELOCK));
            token = L2ArbitrumToken(payable(L2_ARB_TOKEN_ADDRESS));
        } else {
            _setMajorDelegates();
            // Deploy token proxy and initialize
            token = L2ArbitrumToken(TestUtil.deployProxy(address(new L2ArbitrumToken())));
            token.initialize(L1_TOKEN_ADDRESS, INITIAL_SUPPLY, TOKEN_OWNER);
            governor = L2ArbitrumGovernorV2(
                payable(TestUtil.deployProxy(address(new L2ArbitrumGovernorV2())))
            );
            timelock =
                ArbitrumTimelock(payable(TestUtil.deployProxy(address(new ArbitrumTimelock()))));
            address[] memory proposers = new address[](1);
            address[] memory executors = new address[](1);
            proposers[0] = address(governor);
            executors[0] = address(governor);
            timelock.initialize(1, proposers, executors);

            // Initialize governor V2
            governor.initialize(
                token,
                TimelockControllerUpgradeable(payable(address(timelock))),
                OWNER,
                VOTING_DELAY,
                VOTING_PERIOD,
                QUORUM_NUMERATOR,
                PROPOSAL_THRESHOLD,
                VOTE_EXTENSION
            );
        }
    }

    function _setMajorDelegates() internal virtual {
        _majorDelegates = new address[](18);
        // Set the major delegates for testing
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

    function _submitProposal(
        uint256 _randomSeed,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) public returns (uint256 _proposalId) {
        vm.prank(_getRandomProposer(_randomSeed));
        _proposalId = governor.propose(_targets, _values, _calldatas, _description);

        vm.roll(block.number + governor.votingDelay() + 1);
    }

    function _submitAndQueueProposal(
        uint256 _randomSeed,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) public returns (uint256 _proposalId) {
        _proposalId = _submitProposal(_randomSeed, _targets, _values, _calldatas, _description);

        for (uint256 i; i < _majorDelegates.length; i++) {
            vm.prank(_majorDelegates[i]);
            governor.castVote(_proposalId, uint8(VoteType.For));
        }
        vm.roll(block.number + governor.votingPeriod() + 1);
        assertEq(
            uint8(governor.state(_proposalId)), uint8(IGovernorUpgradeable.ProposalState.Succeeded)
        );

        governor.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
    }

    function _submitQueueAndExecuteProposal(
        uint256 _randomSeed,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) public returns (uint256 _proposalId) {
        _proposalId = _submitAndQueueProposal(
            _randomSeed, _targets, _values, _calldatas, _description
        );
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        governor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));
    }

    function _executeUpgradeProposal() internal virtual {
        (
            address[] memory _targets,
            uint256[] memory _values,
            bytes[] memory _calldatas,
            string memory _description,
            uint256 _proposalId
        ) = submitUpgradeProposalScript.run(address(multiProxyUpgradeAction), L1_TIMELOCK_MIN_DELAY);

        // Activate proposal
        vm.roll(block.number + currentCoreGovernor.votingDelay() + 1);

        // Vote
        for (uint256 i; i < _majorDelegates.length; i++) {
            vm.prank(_majorDelegates[i]);
            currentCoreGovernor.castVote(_proposalId, uint8(VoteType.For));
        }

        // Success
        vm.roll(block.number + currentCoreGovernor.votingPeriod() + 1);

        // Queue
        currentCoreGovernor.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
        vm.warp(block.timestamp + currentCoreTimelock.getMinDelay() + 1);

        // Execute
        currentCoreGovernor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));
    }

    function _shouldPassAndExecuteUpgradeProposal() internal pure virtual returns (bool) {
        return true;
    }

    function _basicProposal()
        internal
        pure
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        )
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(0x1234);
        values[0] = 0;
        calldatas[0] = bytes("");
        description = "Test";
    }

    function _getRandomProposer(uint256 _randomSeed) internal view returns (address) {
        uint256 randomIndex = _randomSeed % _majorDelegates.length;
        return _majorDelegates[randomIndex];
    }
}

abstract contract Cancel is L2ArbitrumGovernorV2Test {
    function testFuzz_CancelsPendingProposal(uint256 _randomSeed) public {
        address _proposer = _getRandomProposer(_randomSeed);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        vm.prank(_proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        assertEq(
            uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Pending)
        );

        vm.prank(_proposer);
        uint256 canceledId =
            governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(canceledId, proposalId);
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernorUpgradeable.ProposalState.Canceled)
        );
    }

    function testFuzz_RevertIf_NotProposer(uint256 _randomSeed, address _actor) public {
        address _proposer = _getRandomProposer(_randomSeed);
        vm.assume(_actor != L2_PROXY_ADMIN_CONTRACT && _actor != _proposer);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        vm.prank(_proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        assertEq(
            uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Pending)
        );

        vm.expectRevert(
            abi.encodeWithSelector(L2ArbitrumGovernorV2.NotProposer.selector, _actor, _proposer)
        );
        vm.prank(_actor);
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
    }

    function testFuzz_RevertIf_ProposalIsActive(uint256 _randomSeed) public {
        address _proposer = _getRandomProposer(_randomSeed);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        vm.prank(_proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);
        assertEq(
            uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Active)
        );

        vm.prank(_proposer);
        vm.expectRevert(
            abi.encodeWithSelector(
                L2ArbitrumGovernorV2.ProposalNotPending.selector,
                IGovernorUpgradeable.ProposalState.Active
            )
        );
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
    }

    function testFuzz_RevertIf_AlreadyCanceled(uint256 _randomSeed) public {
        address _proposer = _getRandomProposer(_randomSeed);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        vm.prank(_proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        assertEq(
            uint256(governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Pending)
        );

        // First cancel
        vm.prank(_proposer);
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernorUpgradeable.ProposalState.Canceled)
        );

        vm.prank(_proposer);
        vm.expectRevert(
            abi.encodeWithSelector(
                L2ArbitrumGovernorV2.ProposalNotPending.selector,
                IGovernorUpgradeable.ProposalState.Canceled
            )
        );
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
    }
}

abstract contract Propose is L2ArbitrumGovernorV2Test {
    function testFuzz_ProposerAboveThresholdCanPropose(uint256 _randomSeed) public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        uint256 _proposalId = _submitProposal(_randomSeed, targets, values, calldatas, description);
        assertEq(
            uint8(governor.state(_proposalId)), uint8(IGovernorUpgradeable.ProposalState.Active)
        );
    }

    function testFuzz_EmitsProposalCreatedEvent(uint256 _randomSeed) public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        uint256 _expectedProposalId =
            governor.hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        uint256 _startBlock = block.number + governor.votingDelay();
        uint256 _endBlock = _startBlock + governor.votingPeriod();

        vm.expectEmit();
        emit ProposalCreated(
            _expectedProposalId,
            _getRandomProposer(_randomSeed),
            targets,
            values,
            new string[](targets.length),
            calldatas,
            _startBlock,
            _endBlock,
            description
        );
        _submitProposal(_randomSeed, targets, values, calldatas, description);
    }

    function testFuzz_ProposerBelowThresholdCannotPropose(address _proposer) public {
        vm.assume(_proposer != L2_PROXY_ADMIN_CONTRACT);
        vm.assume(governor.getVotes(_proposer, block.number - 1) < governor.proposalThreshold());
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        vm.expectRevert("Governor: proposer votes below proposal threshold");
        vm.prank(_proposer);
        governor.propose(targets, values, calldatas, description);
    }
}

abstract contract Queue is L2ArbitrumGovernorV2Test {
    function testFuzz_QueuesASucceededProposal(uint256 _randomSeed) public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        uint256 _proposalId =
            _submitAndQueueProposal(_randomSeed, targets, values, calldatas, description);
        assertEq(
            uint8(governor.state(_proposalId)), uint8(IGovernorUpgradeable.ProposalState.Queued)
        );
    }

    function testFuzz_EmitsQueueEvent(uint256 _randomSeed, address _actor) public {
        vm.assume(_actor != L2_PROXY_ADMIN_CONTRACT);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        uint256 _eta = block.timestamp + timelock.getMinDelay();
        uint256 _proposalId = _submitProposal(_randomSeed, targets, values, calldatas, description);

        for (uint256 i; i < _majorDelegates.length; i++) {
            vm.prank(_majorDelegates[i]);
            governor.castVote(_proposalId, uint8(VoteType.For));
        }
        vm.roll(block.number + governor.votingPeriod() + 1);

        vm.expectEmit();
        emit ProposalQueued(_proposalId, _eta);
        vm.prank(_actor);
        governor.queue(targets, values, calldatas, keccak256(bytes(description)));
    }

    function testFuzz_RevertIf_ProposalIsNotSucceeded(uint256 _randomSeed, address _actor) public {
        vm.assume(_actor != L2_PROXY_ADMIN_CONTRACT);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        uint256 _proposalId = _submitProposal(_randomSeed, targets, values, calldatas, description);

        for (uint256 i; i < _majorDelegates.length; i++) {
            vm.prank(_majorDelegates[i]);
            governor.castVote(_proposalId, uint8(VoteType.Against));
        }
        vm.roll(block.number + governor.votingPeriod() + 1);

        vm.prank(_actor);
        vm.expectRevert("Governor: proposal not successful");
        governor.queue(targets, values, calldatas, keccak256(bytes(description)));
    }
}

abstract contract Execute is L2ArbitrumGovernorV2Test {
    function testFuzz_ExecutesASucceededProposal(uint256 _randomSeed) public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        uint256 _proposalId =
            _submitQueueAndExecuteProposal(_randomSeed, targets, values, calldatas, description);
        assertEq(
            uint8(governor.state(_proposalId)), uint8(IGovernorUpgradeable.ProposalState.Executed)
        );
    }

    function testFuzz_EmitsExecuteEvent(uint256 _randomSeed, address _actor) public {
        vm.assume(_actor != L2_PROXY_ADMIN_CONTRACT);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        uint256 _proposalId =
            _submitAndQueueProposal(_randomSeed, targets, values, calldatas, description);
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        vm.expectEmit();
        emit ProposalExecuted(_proposalId);
        vm.prank(_actor);
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function testFuzz_RevertIf_OperationNotReady(uint256 _randomSeed, address _actor) public {
        vm.assume(_actor != L2_PROXY_ADMIN_CONTRACT);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        _submitAndQueueProposal(_randomSeed, targets, values, calldatas, description);

        vm.prank(_actor);
        vm.expectRevert(bytes("TimelockController: operation is not ready"));
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }
}

contract GovernorCancel is Cancel {
    function setUp() public override(L2ArbitrumGovernorV2Test) {
        super.setUp();
    }
}

contract GovernorPropose is Propose {
    function setUp() public override(L2ArbitrumGovernorV2Test) {
        super.setUp();
    }
}

contract GovernorQueue is Queue {
    function setUp() public override(L2ArbitrumGovernorV2Test) {
        super.setUp();
    }
}

contract GovernorExecute is Execute {
    function setUp() public override(L2ArbitrumGovernorV2Test) {
        super.setUp();
    }
}
