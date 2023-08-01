// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";

/// @title  ArbitrumGovernorProposalExpirationUpgradeable
/// @notice GovernorUpgradeable whose proposals expire after a certain amount of time
///         Proposals that have succeeded transition to the Expired state after the expiration time
abstract contract ArbitrumGovernorProposalExpirationUpgradeable is
    Initializable,
    GovernorUpgradeable
{
    /// @notice The number of blocks after which a Succeeeded proposal transitions to Expired
    uint256 public proposalExpirationBlocks;

    function __ArbitrumGovernorProposalExpirationUpgradeable_init(uint256 _proposalExpirationBlocks)
        internal
        onlyInitializing
    {
        __ArbitrumGovernorProposalExpirationUpgradeable_init_unchained(_proposalExpirationBlocks);
    }

    function __ArbitrumGovernorProposalExpirationUpgradeable_init_unchained(
        uint256 _proposalExpirationBlocks
    ) internal onlyInitializing {
        proposalExpirationBlocks = _proposalExpirationBlocks;
    }

    /// @notice Returns the state of a proposal, given its id
    /// @dev    Overridden to return Expired if the proposal has succeeded but has expired
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

    /// @notice The block at which the proposal expires
    function proposalExpirationDeadline(uint256 proposalId) public view returns (uint256) {
        return _proposalExpirationCountdownStart(proposalId) + proposalExpirationBlocks;
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
    uint256[49] private __gap;
}
