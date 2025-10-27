// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import {Test} from "forge-std/Test.sol";
import {SubmitUpgradeProposalScript} from "scripts/forge-scripts/SubmitUpgradeProposalScript.s.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {
    MultiProxyUpgradeAction
} from "src/gov-action-contracts/gov-upgrade-contracts/upgrade-proxy/MultiProxyUpgradeAction.sol";
import {SetupNewGovernors} from "test/util/SetupNewGovernors.sol";
import {
    ProxyUpgradeAndCallAction
} from "src/gov-action-contracts/gov-upgrade-contracts/upgrade-proxy/ProxyUpgradeAndCallAction.sol";
import {L2ArbitrumGovernorV2} from "src/L2ArbitrumGovernorV2.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {L2ArbitrumGovernorV2Test} from "test/L2ArbitrumGovernorV2.t.sol";

contract SubmitUpgradeProposalTest is SetupNewGovernors, L2ArbitrumGovernorV2Test {
    event Upgraded(address indexed implementation);

    function setUp() public virtual override(SetupNewGovernors, L2ArbitrumGovernorV2Test) {
        SetupNewGovernors.setUp();
        _setMajorDelegates();
    }

    function test_SuccessfullyExecuteUpgradeProposal() public {
        MultiProxyUpgradeAction multiProxyUpgradeAction = new MultiProxyUpgradeAction(
            L2_PROXY_ADMIN_CONTRACT,
            L2_CORE_GOVERNOR,
            L2_TREASURY_GOVERNOR,
            address(newGovernorImplementation)
        );

        // Propose
        (
            address[] memory _targets,
            uint256[] memory _values,
            bytes[] memory _calldatas,
            string memory _description,
            uint256 _proposalId
        ) = submitUpgradeProposalScript.run(address(multiProxyUpgradeAction), L1_TIMELOCK_MIN_DELAY);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Pending)
        );
        vm.roll(block.number + currentCoreGovernor.votingDelay() + 1);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Active)
        );

        // Vote
        for (uint256 i; i < _majorDelegates.length; i++) {
            vm.prank(_majorDelegates[i]);
            currentCoreGovernor.castVote(_proposalId, uint8(VoteType.For));
        }

        // Success
        vm.roll(block.number + currentCoreGovernor.votingPeriod() + 1);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Succeeded)
        );

        // Queue
        currentCoreGovernor.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Queued)
        );
        vm.warp(block.timestamp + currentCoreTimelock.getMinDelay() + 1);

        vm.expectEmit();
        emit Upgraded(address(newGovernorImplementation));
        vm.expectEmit();
        emit Upgraded(address(newGovernorImplementation));

        // Execute
        currentCoreGovernor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));

        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Executed)
        );
        assertEq(
            ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
                .getProxyImplementation(
                    TransparentUpgradeableProxy(payable(address(currentCoreGovernor)))
                ),
            address(newGovernorImplementation)
        );
        assertEq(
            ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
                .getProxyImplementation(
                    TransparentUpgradeableProxy(payable(address(currentTreasuryGovernor)))
                ),
            address(newGovernorImplementation)
        );
        assertEq(
            ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
                .getProxyAdmin(TransparentUpgradeableProxy(payable(L2_CORE_GOVERNOR))),
            L2_PROXY_ADMIN_CONTRACT
        );
        assertEq(
            ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
                .getProxyAdmin(TransparentUpgradeableProxy(payable(L2_TREASURY_GOVERNOR))),
            L2_PROXY_ADMIN_CONTRACT
        );
    }

    function test_DefeatedExecuteUpgradeProposalDoesNotUpdateImplementation() public {
        address initialCoreGovernorImplementation = ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
            .getProxyImplementation(
                TransparentUpgradeableProxy(payable(address(currentCoreGovernor)))
            );

        address initialTreasuryGovernorImplementation = ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
            .getProxyImplementation(
                TransparentUpgradeableProxy(payable(address(currentTreasuryGovernor)))
            );

        MultiProxyUpgradeAction multiProxyUpgradeAction = new MultiProxyUpgradeAction(
            L2_PROXY_ADMIN_CONTRACT,
            L2_CORE_GOVERNOR,
            L2_TREASURY_GOVERNOR,
            address(newGovernorImplementation)
        );

        // Propose
        (

            /*address[] memory _targets*/,
            /*uint256[] memory _values*/,
            /*bytes[] memory _calldatas*/,
            /*string memory _description*/,
            uint256 _proposalId
        ) = submitUpgradeProposalScript.run(address(multiProxyUpgradeAction), L1_TIMELOCK_MIN_DELAY);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Pending)
        );
        vm.roll(block.number + currentCoreGovernor.votingDelay() + 1);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Active)
        );

        // Vote
        for (uint256 i; i < _majorDelegates.length; i++) {
            vm.prank(_majorDelegates[i]);
            currentCoreGovernor.castVote(_proposalId, uint8(VoteType.Against));
        }

        // Defeat
        vm.roll(block.number + currentCoreGovernor.votingPeriod() + 1);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Defeated)
        );

        assertEq(
            ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
                .getProxyImplementation(
                    TransparentUpgradeableProxy(payable(address(currentCoreGovernor)))
                ),
            initialCoreGovernorImplementation
        );
        assertEq(
            ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
                .getProxyImplementation(
                    TransparentUpgradeableProxy(payable(address(currentTreasuryGovernor)))
                ),
            initialTreasuryGovernorImplementation
        );
    }
}

interface IUpgradeExecutor {
    function execute(address to, bytes calldata data) external payable;
}
