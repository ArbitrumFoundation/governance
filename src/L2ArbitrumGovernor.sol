// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/compatibility/GovernorCompatibilityBravoUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// CHRIS: TODO: proposalThreshold should use custom calculation?
// CHRIS: TODO: What is timelock conttroller vs timelockcontrollercompound?
// TODO: should we use GovernorPreventLateQuorumUpgradeable?
// CHRIS: TODO: check the inheritance tree
// CHRIS: TODO: should governance be able to set the executor?

/// @title  L2ArbitrumGovernor
/// @notice Governance controls for the Arbitrum DAO
/// @dev    Standard CompBravo compatible governor with some special functionality to avoid counting
///         votes of some excluded tokens.
contract L2ArbitrumGovernor is
    Initializable,
    GovernorSettingsUpgradeable,
    GovernorCompatibilityBravoUpgradeable,
    GovernorVotesUpgradeable,
    GovernorTimelockControlUpgradeable,
    GovernorVotesQuorumFractionUpgradeable
{
    /// @notice address for which votes will not be counted toward quorum
    /// @dev    A portion of the Arbitrum tokebs will be held by entities (eg the treasury) that
    ///         are not eligible to vote. However, even if their voting/delegation is restricted their
    ///         tokens will still count towards the total supply, and will therefore affect the quorom.
    ///         Restricted addresses should be forced to delegate their votes to this special exclude
    ///         addresses which is not counted when calculating quorum
    ///         Example address that should be excluded: DAO treasury, foundation, unclaimed tokens,
    ///         burned tokens and swept (see TokenDistributor) tokens.
    ///         Note that Excluded Address is a readable name with no code of PK associated with it, and thus can't vote. 
    address public constant EXCLUDE_ADDRESS = address(0xA4b86);
    address public l2Executor;

    constructor() {
        _disableInitializers();
    }

    /// @param _token The token to read vote delegation from
    /// @param _timelock A time lock for proposal execution
    /// @param _l2Executor The executor through which all upgrades should be finalised
    /// @param _votingDelay The delay between a proposal submission and voting starts
    /// @param _votingPeriod The period for which the vote lasts
    /// @param _quorumNumerator The proportion of the circulating supply required to reach a quorum
    /// @param _proposalThreshold The number of delegated votes required to create a proposal
    function initialize(
        IVotesUpgradeable _token,
        TimelockControllerUpgradeable _timelock,
        address _l2Executor,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumNumerator,
        uint256 _proposalThreshold
    ) external initializer {
        __Governor_init("L2ArbitrumGovernor");
        __GovernorSettings_init(_votingDelay, _votingPeriod, _proposalThreshold);
        __GovernorCompatibilityBravo_init();
        __GovernorVotes_init(_token);
        __GovernorTimelockControl_init(_timelock);
        __GovernorVotesQuorumFraction_init(_quorumNumerator);
        l2Executor = _l2Executor;
    }

    /// @notice returns l2 executor address; used internally for onlyFromGovernor check
    function _executor()
        internal
        view
        override (GovernorTimelockControlUpgradeable, GovernorUpgradeable)
        returns (address)
    {
        return l2Executor;
    }

    /// @notice Get "circulating" votes supply; i.e., total minus excluded vote exclude address.
    function getPastCirculatingSupply(uint256 blockNumber) public view virtual returns (uint256) {
        return token.getPastTotalSupply(blockNumber) - token.getPastVotes(EXCLUDE_ADDRESS, blockNumber);
    }

    /// @notice Calculates the quorum size, excludes token delegated to the exclude address
    function quorum(uint256 blockNumber)
        public
        view
        override (IGovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable)
        returns (uint256)
    {
        return getPastCirculatingSupply(blockNumber) * quorumNumerator(blockNumber) / quorumDenominator();
    }


    /// @notice Update L2 executor address. Only callable by governance.
    function setL2Executor(address _l2Executor) public onlyGovernance {
        l2Executor = _l2Executor;
    }

    // @notice Votes required for proposal.
    function proposalThreshold()
        public
        view
        override (GovernorSettingsUpgradeable, GovernorUpgradeable)
        returns (uint256)
    {
        return GovernorSettingsUpgradeable.proposalThreshold();
    }

    // Overrides:

    function state(uint256 proposalId)
        public
        view
        override (GovernorUpgradeable, IGovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (ProposalState)
    {
        return GovernorTimelockControlUpgradeable.state(proposalId);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    )
        public
        override (GovernorUpgradeable, GovernorCompatibilityBravoUpgradeable, IGovernorUpgradeable)
        returns (uint256)
    {
        return GovernorCompatibilityBravoUpgradeable.propose(targets, values, calldatas, description);
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override (GovernorUpgradeable, GovernorTimelockControlUpgradeable) {
        GovernorTimelockControlUpgradeable._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override (GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint256) {
        return GovernorTimelockControlUpgradeable._cancel(targets, values, calldatas, descriptionHash);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override (GovernorUpgradeable, IERC165Upgradeable, GovernorTimelockControlUpgradeable)
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
