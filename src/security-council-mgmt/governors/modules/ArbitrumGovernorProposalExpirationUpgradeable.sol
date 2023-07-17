// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";

/// @title ArbitrumGovernorProposalExpirationUpgradeable
/// @notice GovernorUpgradeable whose proposals expire after a certain amount of time
abstract contract ArbitrumGovernorProposalExpirationUpgradeable is
    Initializable,
    GovernorUpgradeable
{
    uint256 constant BLOCK_TIME = 12;

    /// @notice Time (in blocks) after which a successful proposal expires
    uint256 public constant PROPOSAL_EXPIRATION = 2 weeks / BLOCK_TIME;

    /// @inheritdoc GovernorUpgradeable
    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        ProposalState currentState = super.state(proposalId);

        if (
            currentState == ProposalState.Succeeded
                && block.number > proposalExpirationDeadline(proposalId)
        ) {
            return ProposalState.Expired;
        }

        return currentState;
    }

    function proposalExpirationDeadline(uint256 proposalId)
        public
        view
        returns (uint256)
    {
        return _proposalExpirationCountdownStart(proposalId) + PROPOSAL_EXPIRATION;
    }

    /// @notice Returns the block number at which the proposal expiration countdown starts
    function _proposalExpirationCountdownStart(uint256 proposalId)
        internal
        view
        virtual
        returns (uint256)
    {
        return proposalDeadline(proposalId);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
