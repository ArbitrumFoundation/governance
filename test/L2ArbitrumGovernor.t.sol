// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;
import "../src/L2ArbitrumGovernor.sol";
import "../src/ArbitrumTimelock.sol";
import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import "../src/L2ArbitrumToken.sol";
import "./util/TestUtil.sol";
import {L2ArbitrumToken} from "src/L2ArbitrumToken.sol";
import {ArbitrumTimelock} from "src/ArbitrumTimelock.sol";
import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {
    IGovernorUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";
import {TestUtil} from "test/util/TestUtil.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import "forge-std/Test.sol";

contract L2ArbitrumGovernorTest is Test {
    address l1TokenAddress = address(137);
    uint256 initialTokenSupply = 50_000;
    address tokenOwner = address(238);
    uint256 votingPeriod = 6;
    uint256 votingDelay = 9;
    address excludeListMember = address(339);
    uint256 quorumNumerator = 500;
    uint256 proposalThreshold = 1;
    uint64 initialVoteExtension = 5;
    address[] stubAddressArray = [address(640)];
    address someRando = address(741);
    address executor = address(842);

    uint256 dvpStartingBlock = 100;

    L2ArbitrumGovernor _governor;
    L2ArbitrumToken _token;
    ArbitrumTimelock _timelock;
    address _governorProxyAdmin;
    address _tokenProxyAdmin;

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
    event ProposalQueued(uint256 proposalId, uint256 eta);
    event ProposalExecuted(uint256 proposalId);

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

    function setUp() public {
        (_governor, _token, _timelock, _governorProxyAdmin, _tokenProxyAdmin) = deployAndInit();
    }

    function deployAndInit()
        public
        returns (L2ArbitrumGovernor, L2ArbitrumToken, ArbitrumTimelock, address, address)
    {
        L2ArbitrumToken token =
            L2ArbitrumToken(TestUtil.deployProxy(address(new L2ArbitrumToken())));
        token.initialize(l1TokenAddress, initialTokenSupply, tokenOwner);
        _tokenProxyAdmin = abi.decode(
            abi.encodePacked(
                vm.load(
                    address(token),
                    0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
                )
            ),
            (address)
        );

        // predict governor address
        address governorAddress =
            computeCreateAddress(address(this), vm.getNonce(address(this)) + 5);
        address[] memory owners = new address[](1);
        owners[0] = governorAddress;

        ArbitrumTimelock timelock =
            ArbitrumTimelock(payable(TestUtil.deployProxy(address(new ArbitrumTimelock()))));
        timelock.initialize(1, owners, owners);
        // timelock.initialize(1, stubAddressArray, stubAddressArray);

        L2ArbitrumGovernor l2ArbitrumGovernor =
            L2ArbitrumGovernor(payable(TestUtil.deployProxy(address(new L2ArbitrumGovernor()))));

        vm.roll(dvpStartingBlock);
        l2ArbitrumGovernor.initialize(
            token,
            timelock,
            executor,
            votingDelay,
            votingPeriod,
            quorumNumerator,
            proposalThreshold,
            initialVoteExtension
        );

        // Grant roles to the governor if address prediction was wrong (e.g., when using --gas-report)
        if (address(l2ArbitrumGovernor) != governorAddress) {
            timelock.grantRole(timelock.PROPOSER_ROLE(), address(l2ArbitrumGovernor));
            timelock.grantRole(timelock.CANCELLER_ROLE(), address(l2ArbitrumGovernor));
            timelock.grantRole(timelock.EXECUTOR_ROLE(), address(l2ArbitrumGovernor));
        }

        _setQuorumMinAndMax(l2ArbitrumGovernor, 1, type(uint224).max);
        _governorProxyAdmin = abi.decode(
            abi.encodePacked(
                vm.load(
                    address(l2ArbitrumGovernor),
                    0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
                )
            ),
            (address)
        );
        return (l2ArbitrumGovernor, token, timelock, _governorProxyAdmin, _tokenProxyAdmin);
    }

    function _setQuorumMinAndMax(L2ArbitrumGovernor l2ArbitrumGovernor, uint256 min, uint256 max)
        internal
    {
        vm.prank(executor);
        l2ArbitrumGovernor.relay(
            address(l2ArbitrumGovernor),
            0,
            abi.encodeWithSelector(l2ArbitrumGovernor.setQuorumMinAndMax.selector, min, max)
        );
    }

    function createAndMintToProposer(uint256 _randomSeed) internal returns (address) {
        address proposer = address(uint160(_randomSeed));
        vm.assume(
            proposer != address(0) && proposer != _governorProxyAdmin && proposer != _tokenProxyAdmin
                && proposer != _governor.EXCLUDE_ADDRESS()
        );
        vm.warp(300_000_000_000_000_000);
        vm.startPrank(tokenOwner);
        _token.mint(proposer, _governor.proposalThreshold());
        vm.stopPrank();
        vm.prank(proposer);
        _token.delegate(proposer);
        vm.roll(dvpStartingBlock + 3);
        return proposer;
    }

    function _basicProposal()
        internal
        pure
        returns (address[] memory, uint256[] memory, bytes[] memory, string memory)
    {
        return (new address[](1), new uint256[](1), new bytes[](1), "test");
    }

    function _submitProposal(
        address _proposer,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) public returns (uint256 _proposalId) {
        vm.prank(_proposer);
        _proposalId = _governor.propose(_targets, _values, _calldatas, _description);

        vm.roll(block.number + _governor.votingDelay() + 1);
    }

    function _submitAndQueueProposal(
        address _proposer,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) public returns (uint256 _proposalId) {
        _proposalId = _submitProposal(_proposer, _targets, _values, _calldatas, _description);

        vm.prank(_proposer);
        _governor.castVote(_proposalId, uint8(VoteType.For));
        vm.roll(block.number + _governor.votingPeriod() + 1);
        assertEq(
            uint8(_governor.state(_proposalId)), uint8(IGovernorUpgradeable.ProposalState.Succeeded)
        );
        _governor.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
        return _proposalId;
    }

    function _submitQueueAndExecuteProposal(
        address _proposer,
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) public returns (uint256 _proposalId) {
        _proposalId = _submitAndQueueProposal(
            _proposer, _targets, _values, _calldatas, _description
        );

        vm.warp(block.timestamp + _timelock.getMinDelay() + 1);
        _governor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));
        return _proposalId;
    }
}

contract MiscTests is L2ArbitrumGovernorTest {
    function testCantReinit() external {
        (
            L2ArbitrumGovernor l2ArbitrumGovernor,
            L2ArbitrumToken token,
            ArbitrumTimelock timelock,,
        ) = deployAndInit();

        vm.expectRevert("Initializable: contract is already initialized");
        l2ArbitrumGovernor.initialize(
            token,
            timelock,
            someRando,
            votingDelay,
            votingPeriod,
            quorumNumerator,
            proposalThreshold,
            initialVoteExtension
        );
    }

    function testProperlyInitialized() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor,,,,) = deployAndInit();
        assertEq(l2ArbitrumGovernor.votingDelay(), votingDelay, "votingDelay not set properly");
        assertEq(l2ArbitrumGovernor.votingPeriod(), votingPeriod, "votingPeriod not set properly");
    }

    function testPastCirculatingSupplyMint() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor, L2ArbitrumToken token,,,) = deployAndInit();

        vm.warp(200_000_000_000_000_000);
        vm.roll(dvpStartingBlock + 2);

        vm.prank(tokenOwner);
        token.mint(someRando, 200);
        vm.roll(dvpStartingBlock + 3);
        assertEq(
            l2ArbitrumGovernor.getPastCirculatingSupply(dvpStartingBlock + 2),
            initialTokenSupply + 200,
            "Mint should be reflected in getPastCirculatingSupply"
        );
        assertEq(
            l2ArbitrumGovernor.quorum(dvpStartingBlock + 2),
            1,
            "Mint should not be reflected in quorum"
        );
    }

    function testPastCirculatingSupplyExclude() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor, L2ArbitrumToken token,,,) = deployAndInit();
        address excludeAddress = l2ArbitrumGovernor.EXCLUDE_ADDRESS();

        vm.roll(dvpStartingBlock + 3);
        vm.warp(300_000_000_000_000_000);
        vm.prank(tokenOwner);
        token.mint(excludeListMember, 300);

        vm.prank(excludeListMember);
        token.delegate(excludeAddress);
        vm.roll(dvpStartingBlock + 4);
        assertEq(
            token.getPastVotes(excludeAddress, dvpStartingBlock + 3), 300, "didn't delegate to votes exclude address"
        );

        assertEq(
            l2ArbitrumGovernor.getPastCirculatingSupply(dvpStartingBlock + 3),
            initialTokenSupply,
            "votes at exlcude-address member shouldn't affect circulating supply"
        );
        assertEq(
            l2ArbitrumGovernor.quorum(dvpStartingBlock + 3),
            1,
            "should have 1 (clamped) because all votes are delegated to exclude-address"
        );
    }

    function testPastCirculatingSupply() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor,,,,) = deployAndInit();

        vm.warp(200_000_000_000_000_000);
        vm.roll(dvpStartingBlock + 2);
        assertEq(
            l2ArbitrumGovernor.getPastCirculatingSupply(dvpStartingBlock + 1),
            initialTokenSupply,
            "Inital supply error"
        );
    }

    function testExecutorPermissions() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor,,,,) = deployAndInit();
        vm.startPrank(executor);

        l2ArbitrumGovernor.relay(
            address(l2ArbitrumGovernor),
            0,
            abi.encodeWithSelector(l2ArbitrumGovernor.setProposalThreshold.selector, 2)
        );
        assertEq(l2ArbitrumGovernor.proposalThreshold(), 2, "Prop threshold");

        l2ArbitrumGovernor.relay(
            address(l2ArbitrumGovernor),
            0,
            abi.encodeWithSelector(l2ArbitrumGovernor.setVotingDelay.selector, 2)
        );
        assertEq(l2ArbitrumGovernor.votingDelay(), 2, "Voting delay");

        l2ArbitrumGovernor.relay(
            address(l2ArbitrumGovernor),
            0,
            abi.encodeWithSelector(l2ArbitrumGovernor.setVotingPeriod.selector, 2)
        );
        assertEq(l2ArbitrumGovernor.votingPeriod(), 2, "Voting period");

        l2ArbitrumGovernor.relay(
            address(l2ArbitrumGovernor),
            0,
            abi.encodeWithSelector(l2ArbitrumGovernor.updateQuorumNumerator.selector, 400)
        );
        assertEq(l2ArbitrumGovernor.quorumNumerator(), 400, "Quorum num");

        l2ArbitrumGovernor.relay(
            address(l2ArbitrumGovernor),
            0,
            abi.encodeWithSelector(l2ArbitrumGovernor.updateTimelock.selector, address(137))
        );
        assertEq(l2ArbitrumGovernor.timelock(), address(137), "Timelock");

        vm.stopPrank();
    }

    function testExecutorPermissionsFail() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor,,,,) = deployAndInit();

        vm.startPrank(someRando);

        vm.expectRevert("Governor: onlyGovernance");
        l2ArbitrumGovernor.setProposalThreshold(2);

        vm.expectRevert("Governor: onlyGovernance");
        l2ArbitrumGovernor.setVotingDelay(2);

        vm.expectRevert("Governor: onlyGovernance");
        l2ArbitrumGovernor.setVotingPeriod(2);

        vm.expectRevert("Governor: onlyGovernance");
        l2ArbitrumGovernor.updateQuorumNumerator(400);

        vm.expectRevert("Governor: onlyGovernance");
        l2ArbitrumGovernor.updateTimelock(TimelockControllerUpgradeable(payable(address(137))));

        vm.expectRevert("Ownable: caller is not the owner");
        l2ArbitrumGovernor.relay(
            address(l2ArbitrumGovernor),
            0,
            abi.encodeWithSelector(l2ArbitrumGovernor.updateQuorumNumerator.selector, 400)
        );

        vm.stopPrank();
    }

    function testDVPQuorumAndClamping() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor, L2ArbitrumToken token,,,) = deployAndInit();

        vm.roll(dvpStartingBlock + 2);
        _setQuorumMinAndMax(l2ArbitrumGovernor, 2000, 4000);
        vm.roll(dvpStartingBlock + 3);

        // delegate some tokens to get into DVP mode
        vm.prank(tokenOwner);
        token.delegate(someRando);
        vm.prank(tokenOwner);
        token.transfer(address(1), 100);
        vm.roll(dvpStartingBlock + 4);

        // test clamping in DVP mode
        _setQuorumMinAndMax(l2ArbitrumGovernor, 10000, 20000);
        vm.roll(dvpStartingBlock + 5);
        _setQuorumMinAndMax(l2ArbitrumGovernor, 1, 2000);
        vm.roll(dvpStartingBlock + 6);
        // we have 0 delegation, and 0 min, so quorum should be 0
        assertEq(l2ArbitrumGovernor.quorum(dvpStartingBlock + 1), 1, "quorum should be clamped to 1 with no delegation");
        
        // we have 0 delegation, and min 2000, so quorum should be clamped to min
        assertEq(l2ArbitrumGovernor.quorum(dvpStartingBlock + 2), 2000, "quorum should be clamped to min 2000");
        assertEq(token.getTotalDelegationAt(dvpStartingBlock + 3), initialTokenSupply - 100, "DVP error");

        // make sure quorum is calculated based on DVP now
        assertEq(
            l2ArbitrumGovernor.quorum(dvpStartingBlock + 3),
            2495, // ((initialTokenSupply - 100) * quorumNumerator) / 10_000,
            "quorum should be based on DVP"
        );
        assertEq(l2ArbitrumGovernor.quorum(dvpStartingBlock + 4), 10000, "quorum should be clamped to min 10000");
        assertEq(l2ArbitrumGovernor.quorum(dvpStartingBlock + 5), 2000, "quorum should be clamped to max 2000");
    }

    function testMinMaxQuorumGetters() external {
        (L2ArbitrumGovernor l2ArbitrumGovernor,,,,) = deployAndInit();

        assertEq(
            l2ArbitrumGovernor.dvpQuorumStartBlock(),
            dvpStartingBlock,
            "dvpQuorumStartBlock not set correctly"
        );

        assertEq(
            l2ArbitrumGovernor.minimumQuorum(dvpStartingBlock - 1),
            0,
            "should be 0 before DVP quorum start block"
        );
        assertEq(
            l2ArbitrumGovernor.maximumQuorum(dvpStartingBlock - 1),
            0,
            "should be 0 before DVP quorum start block"
        );

        vm.roll(dvpStartingBlock + 2);

        _setQuorumMinAndMax(l2ArbitrumGovernor, 1234, 5678);
        vm.roll(dvpStartingBlock + 3);

        assertEq(
            l2ArbitrumGovernor.minimumQuorum(dvpStartingBlock + 2),
            1234,
            "minimum quorum not set correctly"
        );
        assertEq(
            l2ArbitrumGovernor.maximumQuorum(dvpStartingBlock + 2),
            5678,
            "maximum quorum not set correctly"
        );
        assertEq(
            l2ArbitrumGovernor.minimumQuorum(block.number - 1),
            1234,
            "current minimum quorum not set correctly"
        );
        assertEq(
            l2ArbitrumGovernor.maximumQuorum(block.number - 1),
            5678,
            "current maximum quorum not set correctly"
        );
    }
}

contract Cancel is L2ArbitrumGovernorTest {
    function testFuzz_CancelsPendingProposal(uint256 _randomSeed) public {
        address _proposer = createAndMintToProposer(_randomSeed);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        vm.prank(_proposer);
        uint256 proposalId = _governor.propose(targets, values, calldatas, description);

        assertEq(
            uint256(_governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Pending)
        );

        vm.prank(_proposer);
        uint256 canceledId =
            _governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(canceledId, proposalId);
        assertEq(
            uint256(_governor.state(proposalId)),
            uint256(IGovernorUpgradeable.ProposalState.Canceled)
        );
    }

    function testFuzz_RevertIf_NotProposer(uint256 _randomSeed, address _actor) public {
        address _proposer = createAndMintToProposer(_randomSeed);
        vm.assume(_actor != _proposer);
        // vm.assume(_actor != proxyAdmin);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        vm.prank(_proposer);
        uint256 proposalId = _governor.propose(targets, values, calldatas, description);

        assertEq(
            uint256(_governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Pending)
        );

        vm.expectRevert("L2ArbitrumGovernor: NOT_PROPOSER");
        vm.prank(_actor);
        _governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
    }

    function testFuzz_RevertIf_ProposalIsActive(uint256 _randomSeed) public {
        address _proposer = createAndMintToProposer(_randomSeed);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        vm.prank(_proposer);
        uint256 proposalId = _governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + _governor.votingDelay() + 1);
        assertEq(
            uint256(_governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Active)
        );

        vm.prank(_proposer);
        vm.expectRevert("L2ArbitrumGovernor: PROPOSAL_NOT_PENDING");
        _governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
    }

    function testFuzz_RevertIf_AlreadyCanceled(uint256 _randomSeed) public {
        address _proposer = createAndMintToProposer(_randomSeed);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        vm.prank(_proposer);
        uint256 proposalId = _governor.propose(targets, values, calldatas, description);
        assertEq(
            uint256(_governor.state(proposalId)), uint256(IGovernorUpgradeable.ProposalState.Pending)
        );

        // First cancel
        vm.prank(_proposer);
        _governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(
            uint256(_governor.state(proposalId)),
            uint256(IGovernorUpgradeable.ProposalState.Canceled)
        );

        vm.prank(_proposer);
        vm.expectRevert("L2ArbitrumGovernor: PROPOSAL_NOT_PENDING");
        _governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
    }
}

contract Propose is L2ArbitrumGovernorTest {
    function testFuzz_ProposerAboveThresholdCanPropose(uint256 _randomSeed) public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        address _proposer = createAndMintToProposer(_randomSeed);
        uint256 _proposalId = _submitProposal(_proposer, targets, values, calldatas, description);
        assertEq(
            uint8(_governor.state(_proposalId)), uint8(IGovernorUpgradeable.ProposalState.Active)
        );
    }

    function testFuzz_EmitsProposalCreatedEvent(uint256 _randomSeed) public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        address _proposer = createAndMintToProposer(_randomSeed);
        uint256 _expectedProposalId =
            _governor.hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        uint256 _startBlock = block.number + _governor.votingDelay();
        uint256 _endBlock = _startBlock + _governor.votingPeriod();

        vm.expectEmit();
        emit ProposalCreated(
            _expectedProposalId,
            _proposer,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            _startBlock,
            _endBlock,
            description
        );
        _submitProposal(_proposer, targets, values, calldatas, description);
    }

    function testFuzz_ProposerBelowThresholdCannotPropose(address _proposer) public {
        vm.assume(_governor.getVotes(_proposer, block.number - 1) < _governor.proposalThreshold());
        vm.assume(_proposer != _governorProxyAdmin);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        vm.expectRevert("Governor: proposer votes below proposal threshold");
        vm.prank(_proposer);
        _governor.propose(targets, values, calldatas, description);
    }
}

contract Queue is L2ArbitrumGovernorTest {
    function testFuzz_QueuesASucceededProposal(uint256 _randomSeed) public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        address _proposer = createAndMintToProposer(_randomSeed);
        uint256 _proposalId =
            _submitAndQueueProposal(_proposer, targets, values, calldatas, description);
        assertEq(
            uint8(_governor.state(_proposalId)), uint8(IGovernorUpgradeable.ProposalState.Queued)
        );
    }

    function testFuzz_EmitsQueueEvent(uint256 _randomSeed) public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        address _proposer = createAndMintToProposer(_randomSeed);
        uint256 _eta = block.timestamp + _timelock.getMinDelay();
        uint256 _proposalId = _submitProposal(_proposer, targets, values, calldatas, description);

        vm.prank(_proposer);
        _governor.castVote(_proposalId, uint8(VoteType.For));
        vm.roll(block.number + _governor.votingPeriod() + 1);

        vm.expectEmit();
        emit ProposalQueued(_proposalId, _eta);
        _governor.queue(targets, values, calldatas, keccak256(bytes(description)));
    }

    function testFuzz_RevertIf_ProposalIsNotSucceeded(uint256 _randomSeed) public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        address _proposer = createAndMintToProposer(_randomSeed);
        uint256 _proposalId = _submitProposal(_proposer, targets, values, calldatas, description);

        vm.prank(_proposer);
        _governor.castVote(_proposalId, uint8(VoteType.Against));
        vm.roll(block.number + _governor.votingPeriod() + 1);

        vm.expectRevert("Governor: proposal not successful");
        _governor.queue(targets, values, calldatas, keccak256(bytes(description)));
    }
}

contract Execute is L2ArbitrumGovernorTest {
    function testFuzz_ExecutesASucceededProposal(uint256 _randomSeed) public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        address _proposer = createAndMintToProposer(_randomSeed);
        uint256 _proposalId =
            _submitQueueAndExecuteProposal(_proposer, targets, values, calldatas, description);
        assertEq(
            uint8(_governor.state(_proposalId)), uint8(IGovernorUpgradeable.ProposalState.Executed)
        );
    }

    function testFuzz_EmitsExecuteEvent(uint256 _randomSeed, address _actor) public {
        vm.assume(_actor != _governorProxyAdmin);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        address _proposer = createAndMintToProposer(_randomSeed);
        uint256 _proposalId =
            _submitAndQueueProposal(_proposer, targets, values, calldatas, description);
        vm.warp(block.timestamp + _timelock.getMinDelay() + 1);

        vm.expectEmit();
        emit ProposalExecuted(_proposalId);
        vm.prank(_actor);
        _governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function testFuzz_RevertIf_OperationNotReady(uint256 _randomSeed, address _actor) public {
        vm.assume(_actor != _governorProxyAdmin);
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _basicProposal();

        address _proposer = createAndMintToProposer(_randomSeed);
        _submitAndQueueProposal(_proposer, targets, values, calldatas, description);

        vm.prank(_actor);
        vm.expectRevert(bytes("TimelockController: operation is not ready"));
        _governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }
}
