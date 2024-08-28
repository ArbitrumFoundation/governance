// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {SubmitUpgradeProposalScript} from "script/SubmitUpgradeProposalScript.s.sol";
import {IGovernor} from "openzeppelin-v5/governance/IGovernor.sol";
import {TimelockRolesUpgrader} from
    "src/gov-action-contracts/gov-upgrade-contracts/update-timelock-roles/TimelockRolesUpgrader.sol";
import {SetupNewGovernors} from "test/util/SetupNewGovernors.sol";

contract SubmitUpgradeProposalTest is SetupNewGovernors {
    function test_SuccessfullyExecuteUpgradeProposal() public {
        TimelockRolesUpgrader timelockRolesUpgrader = new TimelockRolesUpgrader(
            L2_CORE_GOVERNOR_TIMELOCK,
            L2_CORE_GOVERNOR,
            L2_CORE_GOVERNOR_NEW_DEPLOY,
            L2_TREASURY_GOVERNOR_TIMELOCK,
            L2_TREASURY_GOVERNOR,
            L2_TREASURY_GOVERNOR_NEW_DEPLOY
        );

        // Propose
        (
            address[] memory _targets,
            uint256[] memory _values,
            bytes[] memory _calldatas,
            string memory _description,
            uint256 _proposalId
        ) = submitUpgradeProposalScript.run(address(timelockRolesUpgrader), L1_TIMELOCK_MIN_DELAY);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Pending)
        );
        vm.roll(vm.getBlockNumber() + currentCoreGovernor.votingDelay() + 1);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Active)
        );

        // Vote
        for (uint256 i; i < _majorDelegates.length; i++) {
            vm.prank(_majorDelegates[i]);
            currentCoreGovernor.castVote(_proposalId, uint8(VoteType.For));
        }

        // Success
        vm.roll(vm.getBlockNumber() + currentCoreGovernor.votingPeriod() + 1);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Succeeded)
        );

        // Queue
        currentCoreGovernor.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Queued)
        );
        vm.warp(vm.getBlockTimestamp() + currentCoreTimelock.getMinDelay() + 1);

        // Execute
        currentCoreGovernor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Executed)
        );

        assertEq(
            currentCoreTimelock.hasRole(keccak256("PROPOSER_ROLE"), address(newCoreGovernor)), true
        );
        assertEq(
            currentCoreTimelock.hasRole(keccak256("CANCELLER_ROLE"), address(newCoreGovernor)), true
        );
        assertEq(currentCoreTimelock.hasRole(keccak256("PROPOSER_ROLE"), L2_CORE_GOVERNOR), false);
        assertEq(currentCoreTimelock.hasRole(keccak256("CANCELLER_ROLE"), L2_CORE_GOVERNOR), false);

        assertEq(
            currentTreasuryTimelock.hasRole(
                keccak256("PROPOSER_ROLE"), address(newTreasuryGovernor)
            ),
            true
        );
        assertEq(
            currentTreasuryTimelock.hasRole(
                keccak256("CANCELLER_ROLE"), address(newTreasuryGovernor)
            ),
            true
        );
        assertEq(
            currentTreasuryTimelock.hasRole(keccak256("PROPOSER_ROLE"), L2_TREASURY_GOVERNOR), false
        );
        assertEq(
            currentTreasuryTimelock.hasRole(keccak256("CANCELLER_ROLE"), L2_TREASURY_GOVERNOR),
            false
        );
    }

    function test_DefeatedExecuteUpgradeProposalDoesNotChangeRoles() public {
        TimelockRolesUpgrader timelockRolesUpgrader = new TimelockRolesUpgrader(
            L2_CORE_GOVERNOR_TIMELOCK,
            L2_CORE_GOVERNOR,
            address(newCoreGovernor),
            L2_TREASURY_GOVERNOR_TIMELOCK,
            L2_TREASURY_GOVERNOR,
            address(newTreasuryGovernor)
        );

        // Propose
        (
            /*address[] memory _targets*/
            ,
            /*uint256[] memory _values*/
            ,
            /*bytes[] memory _calldatas*/
            ,
            /*string memory _description*/
            ,
            uint256 _proposalId
        ) = submitUpgradeProposalScript.run(address(timelockRolesUpgrader), L1_TIMELOCK_MIN_DELAY);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Pending)
        );
        vm.roll(vm.getBlockNumber() + currentCoreGovernor.votingDelay() + 1);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Active)
        );

        // Vote
        for (uint256 i; i < _majorDelegates.length; i++) {
            vm.prank(_majorDelegates[i]);
            currentCoreGovernor.castVote(_proposalId, uint8(VoteType.Against));
        }

        // Defeat
        vm.roll(vm.getBlockNumber() + currentCoreGovernor.votingPeriod() + 1);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Defeated)
        );

        assertEq(
            currentCoreTimelock.hasRole(keccak256("PROPOSER_ROLE"), address(newCoreGovernor)), false
        );
        assertEq(
            currentCoreTimelock.hasRole(keccak256("CANCELLER_ROLE"), address(newCoreGovernor)),
            false
        );
        assertEq(currentCoreTimelock.hasRole(keccak256("PROPOSER_ROLE"), L2_CORE_GOVERNOR), true);
        assertEq(currentCoreTimelock.hasRole(keccak256("CANCELLER_ROLE"), L2_CORE_GOVERNOR), true);

        assertEq(
            currentTreasuryTimelock.hasRole(
                keccak256("PROPOSER_ROLE"), address(newTreasuryGovernor)
            ),
            false
        );
        assertEq(
            currentTreasuryTimelock.hasRole(
                keccak256("CANCELLER_ROLE"), address(newTreasuryGovernor)
            ),
            false
        );
        assertEq(
            currentTreasuryTimelock.hasRole(keccak256("PROPOSER_ROLE"), L2_TREASURY_GOVERNOR), true
        );
        assertEq(
            currentTreasuryTimelock.hasRole(keccak256("CANCELLER_ROLE"), L2_TREASURY_GOVERNOR), true
        );
    }
}

interface IUpgradeExecutor {
    function execute(address to, bytes calldata data) external payable;
}
