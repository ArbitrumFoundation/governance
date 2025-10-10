// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {
    L2ArbitrumGovernor,
    GovernorUpgradeable,
    IGovernorUpgradeable
} from "src/L2ArbitrumGovernor.sol";

contract L2ArbitrumGovernorV2 is L2ArbitrumGovernor {
    /// @notice Error thrown when attempting to cancel a proposal that is not in Pending state.
    /// @param state The current state of the proposal.
    error ProposalNotPending(GovernorUpgradeable.ProposalState state);

    /// @notice Error thrown when a non-proposer attempts to cancel a proposal.
    /// @param sender The address attempting to cancel the proposal.
    /// @param proposer The address of the actual proposer.
    error NotProposer(address sender, address proposer);

    /// @notice Mapping from proposal ID to the address of the proposer.
    /// @dev Used in cancel() to ensure only the proposer can cancel the proposal.
    mapping(uint256 => address) internal proposers;

    /// @inheritdoc IGovernorUpgradeable
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override(IGovernorUpgradeable, GovernorUpgradeable) returns (uint256) {
        uint256 _proposalId = GovernorUpgradeable.propose(targets, values, calldatas, description);
        proposers[_proposalId] = msg.sender;
        return _proposalId;
    }

    /// @notice Allows a proposer to cancel a proposal when it is pending.
    /// @param targets The proposal's targets.
    /// @param values The proposal's values.
    /// @param calldatas The proposal's calldatas.
    /// @param descriptionHash The hash of the proposal's description.
    /// @return The id of the proposal.
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual returns (uint256) {
        uint256 _proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        if (state(_proposalId) != ProposalState.Pending) {
            revert ProposalNotPending(state(_proposalId));
        }

        address _proposer = proposers[_proposalId];
        if (msg.sender != _proposer) {
            revert NotProposer(msg.sender, _proposer);
        }

        delete proposers[_proposalId];

        return GovernorUpgradeable._cancel(targets, values, calldatas, descriptionHash);
    }
}
