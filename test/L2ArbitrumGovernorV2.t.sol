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

contract L2ArbitrumGovernorV2Test is Test {
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

    function setUp() public virtual {
        // Deploy token proxy and initialize
        token = L2ArbitrumToken(TestUtil.deployProxy(address(new L2ArbitrumToken())));
        token.initialize(L1_TOKEN_ADDRESS, INITIAL_SUPPLY, TOKEN_OWNER);
        governor = L2ArbitrumGovernorV2(
            payable(TestUtil.deployProxy(address(new L2ArbitrumGovernorV2())))
        );
        timelock = ArbitrumTimelock(payable(TestUtil.deployProxy(address(new ArbitrumTimelock()))));
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
}

abstract contract Cancel is L2ArbitrumGovernorV2Test {
    function testFuzz_CancelsPendingProposal(address _proposer) public {
        vm.assume(_proposer != address(0));
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

    function testFuzz_RevertIf_NotProposer(address _proposer, address _actor) public {
        vm.assume(_proposer != address(0));
        vm.assume(_actor != _proposer && _actor != PROXY_ADMIN);
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

    function testFuzz_RevertIf_ProposalIsActive(address _proposer) public {
        vm.assume(_proposer != address(0));
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

    function testFuzz_RevertIf_AlreadyCanceled(address _proposer) public {
        vm.assume(_proposer != address(0));
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

contract MockGovernorCancel is Cancel {
    function setUp() public override(L2ArbitrumGovernorV2Test) {
        super.setUp();
    }
}
