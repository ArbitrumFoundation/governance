// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";

/// @title ArbitrumGovernorVotesQuorumFractionUpgradeable
/// @notice GovernorVotesQuorumFractionUpgradeable with a quorum that excludes a special address
abstract contract ArbitrumGovernorVotesQuorumFractionUpgradeable is
    Initializable,
    GovernorVotesQuorumFractionUpgradeable
{
    /// @notice address for which votes will not be counted toward quorum
    /// @dev    A portion of the Arbitrum tokens will be held by entities (eg the treasury) that
    ///         are not eligible to vote. However, even if their voting/delegation is restricted their
    ///         tokens will still count towards the total supply, and will therefore affect the quorum.
    ///         Restricted addresses should be forced to delegate their votes to this special exclude
    ///         addresses which is not counted when calculating quorum
    ///         Example address that should be excluded: DAO treasury, foundation, unclaimed tokens,
    ///         burned tokens and swept (see TokenDistributor) tokens.
    ///         Note that Excluded Address is a readable name with no code or PK associated with it, and thus can't vote.
    address public constant EXCLUDE_ADDRESS = address(0xA4b86);

    function __ArbitrumGovernorVotesQuorumFraction_init(uint256 quorumNumeratorValue)
        internal
        onlyInitializing
    {
        __GovernorVotesQuorumFraction_init(quorumNumeratorValue);
    }

    /// @notice Get "circulating" votes supply; i.e., total minus excluded vote exclude address.
    function getPastCirculatingSupply(uint256 blockNumber) public view virtual returns (uint256) {
        return
            token.getPastTotalSupply(blockNumber) - token.getPastVotes(EXCLUDE_ADDRESS, blockNumber);
    }

    /// @notice Calculates the quorum size, excludes token delegated to the exclude address
    function quorum(uint256 blockNumber) public view virtual override returns (uint256) {
        return (getPastCirculatingSupply(blockNumber) * quorumNumerator(blockNumber))
            / quorumDenominator();
    }

    /// @inheritdoc GovernorVotesQuorumFractionUpgradeable
    function quorumDenominator() public pure virtual override returns (uint256) {
        // update to 10k to allow for higher precision
        return 10_000;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
