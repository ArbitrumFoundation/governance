// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorPreventLateQuorumUpgradeable.sol";
import
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title  L2ArbitrumGovernor
/// @notice Governance controls for the Arbitrum DAO
/// @dev    Standard governor with some special functionality to avoid counting
///         votes of some excluded tokens. Also allows for an owner to set parameters by calling
///         relay.
contract L2ArbitrumGovernor is
    Initializable,
    GovernorSettingsUpgradeable,
    GovernorCountingSimpleUpgradeable,
    GovernorVotesUpgradeable,
    GovernorTimelockControlUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    GovernorPreventLateQuorumUpgradeable,
    OwnableUpgradeable
{
    /// @notice address for which votes will not be counted toward quorum
    /// @dev    A portion of the Arbitrum tokens will be held by entities (eg the treasury) that
    ///         are not eligible to vote. However, even if their voting/delegation is restricted their
    ///         tokens will still count towards the total supply, and will therefore affect the quorum.
    ///         Restricted addresses should be forced to delegate their votes to this special exclude
    ///         addresses which is not counted when calculating quorum
    ///         Example address that should be excluded: DAO treasury, foundation, unclaimed tokens,
    ///         burned tokens and swept (see TokenDistributor) tokens.
    ///         Note that Excluded Address is a readable name with no code of PK associated with it, and thus can't vote.
    address public constant EXCLUDE_ADDRESS = address(0xA4b86);

    constructor() {
        _disableInitializers();
    }

    /// @param _token The token to read vote delegation from
    /// @param _timelock A time lock for proposal execution
    /// @param _owner The executor through which all upgrades should be finalised
    /// @param _votingDelay The delay between a proposal submission and voting starts
    /// @param _votingPeriod The period for which the vote lasts
    /// @param _quorumNumerator The proportion of the circulating supply required to reach a quorum
    /// @param _proposalThreshold The number of delegated votes required to create a proposal
    /// @param _minPeriodAfterQuorum The minimum number of blocks available for voting after the quorum is reached
    function initialize(
        IVotesUpgradeable _token,
        TimelockControllerUpgradeable _timelock,
        address _owner,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumNumerator,
        uint256 _proposalThreshold,
        uint64 _minPeriodAfterQuorum
    ) external initializer {
        __Governor_init("L2ArbitrumGovernor");
        __GovernorSettings_init(_votingDelay, _votingPeriod, _proposalThreshold);
        __GovernorCountingSimple_init();
        __GovernorVotes_init(_token);
        __GovernorTimelockControl_init(_timelock);
        __GovernorVotesQuorumFraction_init(_quorumNumerator);
        __GovernorPreventLateQuorum_init(_minPeriodAfterQuorum);
        _transferOwnership(_owner);
    }

    /// @notice Allows the owner to make calls from the governor
    /// @dev    We want the owner to be able to upgrade settings and parametes on this Governor
    ///         however we can't use onlyGovernance as it requires calls originate from the governor
    ///         contract. The normal flow for onlyGovernance to work is to call execute on the governor
    ///         which will then call out to the _executor(), which will then call back in to the governor to set
    ///         a parameter. At the point of setting the parameter onlyGovernance is checked, and this includes
    ///         a check this call originated in the execute() function. The purpose of this is an added
    ///         safety measure that ensure that all calls originate at the governor, and if second entrypoint is
    ///         added to the _executor() contract, that new entrypoint will not be able to pass the onlyGovernance check.
    ///         You can read more about this in the comments on onlyGovernance()
    ///         This flow doesn't work for Arbitrum governance as we require an proposal on L2 to first
    ///         be relayed to L1, and then back again to L2 before calling into the governor to update
    ///         settings. This means that updating settings can't be done in a single transaction.
    ///         There are two potential solutions to this problem:
    ///         1.  Use a more persistent record that a specific upgrade is taking place. This adds
    ///             a lot of complexity, as we have multiple layers of calldata wrapping each other to
    ///             define the multiple transactions that occur in a round-trip upgrade. So safely recording
    ///             execution of the would be difficult and brittle.
    ///         2.  Override this protection and just ensure elsewhere that the executor only has the
    ///             the correct entrypoints and access control. We've gone for this option.
    ///         By overriding the relay function we allow the executor to make any call originating
    ///         from the governor, and by setting the _executor() to be the governor itself we can use the
    ///         relay function to call back into the governor to update settings e.g:
    ///
    ///         l2ArbitrumGovernor.relay(
    ///             address(l2ArbitrumGovernor),
    ///             0,
    ///             abi.encodeWithSelector(l2ArbitrumGovernor.updateQuorumNumerator.selector, 4)
    ///         );
    function relay(address target, uint256 value, bytes calldata data)
        external
        virtual
        override
        onlyOwner
    {
        AddressUpgradeable.functionCallWithValue(target, data, value);
    }

    /// @notice returns l2 executor address; used internally for onlyGovernance check
    function _executor()
        internal
        view
        override(GovernorTimelockControlUpgradeable, GovernorUpgradeable)
        returns (address)
    {
        return address(this);
    }

    /// @notice Get "circulating" votes supply; i.e., total minus excluded vote exclude address.
    function getPastCirculatingSupply(uint256 blockNumber) public view virtual returns (uint256) {
        return
            token.getPastTotalSupply(blockNumber) - token.getPastVotes(EXCLUDE_ADDRESS, blockNumber);
    }

    /// @notice Calculates the quorum size, excludes token delegated to the exclude address
    function quorum(uint256 blockNumber)
        public
        view
        override(IGovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable)
        returns (uint256)
    {
        return (getPastCirculatingSupply(blockNumber) * quorumNumerator(blockNumber))
            / quorumDenominator();
    }

    /// @inheritdoc GovernorVotesQuorumFractionUpgradeable
    function quorumDenominator()
        public
        pure
        override(GovernorVotesQuorumFractionUpgradeable)
        returns (uint256)
    {
        // update to 10k to allow for higher precision
        return 10_000;
    }

    // Overrides:

    // @notice Votes required for proposal.
    function proposalThreshold()
        public
        view
        override(GovernorSettingsUpgradeable, GovernorUpgradeable)
        returns (uint256)
    {
        return GovernorSettingsUpgradeable.proposalThreshold();
    }

    function state(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (ProposalState)
    {
        return GovernorTimelockControlUpgradeable.state(proposalId);
    }

    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    )
        internal
        override(GovernorUpgradeable, GovernorPreventLateQuorumUpgradeable)
        returns (uint256)
    {
        return GovernorPreventLateQuorumUpgradeable._castVote(
            proposalId, account, support, reason, params
        );
    }

    function proposalDeadline(uint256 proposalId)
        public
        view
        override(IGovernorUpgradeable, GovernorUpgradeable, GovernorPreventLateQuorumUpgradeable)
        returns (uint256)
    {
        return GovernorPreventLateQuorumUpgradeable.proposalDeadline(proposalId);
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) {
        GovernorTimelockControlUpgradeable._execute(
            proposalId, targets, values, calldatas, descriptionHash
        );
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (uint256)
    {
        return
            GovernorTimelockControlUpgradeable._cancel(targets, values, calldatas, descriptionHash);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (bool)
    {
        return GovernorTimelockControlUpgradeable.supportsInterface(interfaceId);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
