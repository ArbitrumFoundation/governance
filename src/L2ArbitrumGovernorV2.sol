// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorSettingsUpgradeable} from
  "openzeppelin-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {GovernorCountingFractionalUpgradeable} from
  "src/lib/governance/extensions/GovernorCountingFractionalUpgradeable.sol";
import {GovernorTimelockControlUpgradeable} from
  "openzeppelin-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import {GovernorVotesQuorumFractionUpgradeable} from
  "openzeppelin-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {GovernorPreventLateQuorumUpgradeable} from
  "openzeppelin-upgradeable/governance/extensions/GovernorPreventLateQuorumUpgradeable.sol";
import {GovernorVotesUpgradeable} from "openzeppelin-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {TimelockControllerUpgradeable} from "openzeppelin-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {IVotes} from "openzeppelin/governance/utils/IVotes.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title L2 Arbitrum Governor V2
/// @notice Governance controls for the Arbitrum DAO
/// @custom:security-contact https://immunefi.com/bug-bounty/arbitrum/information/
contract L2ArbitrumGovernorV2 is
  Initializable,
  GovernorSettingsUpgradeable,
  GovernorCountingFractionalUpgradeable,
  GovernorVotesUpgradeable,
  GovernorTimelockControlUpgradeable,
  GovernorVotesQuorumFractionUpgradeable,
  GovernorPreventLateQuorumUpgradeable,
  OwnableUpgradeable
{
  /// @notice Error thrown when canceling a non-pending proposal.
  error ProposalNotPending(GovernorUpgradeable.ProposalState state);

  /// @notice address for which votes will not be counted toward quorum.
  /// @dev    A portion of the Arbitrum tokens will be held by entities (eg the treasury) that
  ///         are not eligible to vote. However, even if their voting/delegation is restricted their
  ///         tokens will still count towards the total supply, and will therefore affect the quorum.
  ///         Restricted addresses should be forced to delegate their votes to this special exclude
  ///         address which is not counted when calculating quorum
  ///         Example addresses that should be excluded: DAO treasury, foundation, unclaimed tokens,
  ///         burned tokens and swept (see TokenDistributor) tokens.
  ///         Note that Excluded Address is a readable name with no code or PK associated with it, and thus can't vote.
  address public constant EXCLUDE_ADDRESS = address(0xA4b86);

  /// @notice Disables the initialize function.
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes the Governor with the provided parameters.
  /// @param _name The name of the Governor.
  /// @param _initialVotingDelay The initial voting delay.
  /// @param _initialVotingPeriod The initial voting period.
  /// @param _initialProposalThreshold The initial proposal threshold.
  /// @param _arbAddress The address of the Arbitrum token.
  /// @param _timelockAddress The address of the Timelock.
  /// @param _quorumNumeratorValue The initial quorum numerator value.
  /// @param _initialVoteExtension The initial vote extension.
  /// @param _initialOwner The initial owner of the Governor.
  function initialize(
    string memory _name,
    uint48 _initialVotingDelay,
    uint32 _initialVotingPeriod,
    uint256 _initialProposalThreshold,
    IVotes _arbAddress,
    TimelockControllerUpgradeable _timelockAddress,
    uint256 _quorumNumeratorValue,
    uint48 _initialVoteExtension,
    address _initialOwner
  ) public initializer {
    __Governor_init(_name);
    __GovernorSettings_init(_initialVotingDelay, _initialVotingPeriod, _initialProposalThreshold);
    __GovernorVotes_init(_arbAddress);
    __GovernorTimelockControl_init(_timelockAddress);
    __GovernorVotesQuorumFraction_init(_quorumNumeratorValue);
    __GovernorPreventLateQuorum_init(_initialVoteExtension);
    __Ownable_init(_initialOwner);
  }

  /// @inheritdoc GovernorVotesQuorumFractionUpgradeable
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function quorumDenominator() public pure override(GovernorVotesQuorumFractionUpgradeable) returns (uint256) {
    // update to 10k to allow for higher precision
    return 10_000;
  }

  /// @inheritdoc GovernorPreventLateQuorumUpgradeable
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function proposalDeadline(uint256 _proposalId)
    public
    view
    virtual
    override(GovernorPreventLateQuorumUpgradeable, GovernorUpgradeable)
    returns (uint256)
  {
    return GovernorPreventLateQuorumUpgradeable.proposalDeadline(_proposalId);
  }

  /// @inheritdoc GovernorTimelockControlUpgradeable
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function proposalNeedsQueuing(uint256 _proposalId)
    public
    view
    virtual
    override(GovernorTimelockControlUpgradeable, GovernorUpgradeable)
    returns (bool)
  {
    return GovernorTimelockControlUpgradeable.proposalNeedsQueuing(_proposalId);
  }

  /// @inheritdoc GovernorSettingsUpgradeable
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function proposalThreshold()
    public
    view
    virtual
    override(GovernorSettingsUpgradeable, GovernorUpgradeable)
    returns (uint256)
  {
    return GovernorSettingsUpgradeable.proposalThreshold();
  }

  /// @inheritdoc GovernorTimelockControlUpgradeable
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function state(uint256 _proposalId)
    public
    view
    virtual
    override(GovernorTimelockControlUpgradeable, GovernorUpgradeable)
    returns (ProposalState)
  {
    return GovernorTimelockControlUpgradeable.state(_proposalId);
  }

  /// @notice Get "circulating" votes supply; i.e., total minus excluded vote exclude address.
  /// @param timepoint The timepoint at which to calculate the circulating supply.
  /// @return The circulating supply of votes.
  function getPastCirculatingSupply(uint256 timepoint) public view virtual returns (uint256) {
    return token().getPastTotalSupply(timepoint) - token().getPastVotes(EXCLUDE_ADDRESS, timepoint);
  }

  /// @notice Calculates the quorum size, excludes token delegated to the exclude address.
  /// @dev We override this function to use the circulating supply to calculate the quorum.
  /// @param timepoint The timepoint at which to calculate the quorum.
  /// @return The quorum size.
  function quorum(uint256 timepoint)
    public
    view
    override(GovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable)
    returns (uint256)
  {
    return (getPastCirculatingSupply(timepoint) * quorumNumerator(timepoint)) / quorumDenominator();
  }

  /// @notice Allows a proposer to cancel a proposal when it is pending.
  /// @param targets A list of target addresses for calls to be made in the proposal.
  /// @param values A list of values (ETH) to be passed to the calls in the proposal.
  /// @param calldatas A list of calldata for the calls in the proposal.
  /// @param descriptionHash The hash of the description for the proposal.
  /// @return The id of the proposal.
  function cancel(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
    public
    override
    returns (uint256)
  {
    uint256 _proposalId = hashProposal(targets, values, calldatas, descriptionHash);
    if (state(_proposalId) != ProposalState.Pending) {
      revert ProposalNotPending(state(_proposalId));
    }
    return GovernorUpgradeable.cancel(targets, values, calldatas, descriptionHash);
  }

  /// @dev Allows a proposer to vote on a proposal during its voting period.
  /// @param _proposalId The id of the proposal.
  /// @param _support The support value for the vote.
  /// @param _reason The reason for the vote.
  /// @param _params Additional parameters for the vote.
  /// @return The voting weight.
  function _castVote(uint256 _proposalId, address _account, uint8 _support, string memory _reason, bytes memory _params)
    internal
    virtual
    override(GovernorPreventLateQuorumUpgradeable, GovernorUpgradeable)
    returns (uint256)
  {
    return GovernorPreventLateQuorumUpgradeable._castVote(_proposalId, _account, _support, _reason, _params);
  }

  /// @dev Allows a proposer to cancel a proposal when it is pending.
  /// @param _targets The list of target addresses for calls to be made in the proposal.
  /// @param _values The list of values (ETH) to be passed to the calls in the proposal.
  /// @param _calldatas The list of calldata for the calls in the proposal.
  /// @param _descriptionHash The hash of the description for the proposal.
  /// @return The id of the proposal.
  function _cancel(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal virtual override(GovernorTimelockControlUpgradeable, GovernorUpgradeable) returns (uint256) {
    return GovernorTimelockControlUpgradeable._cancel(_targets, _values, _calldatas, _descriptionHash);
  }

  /// @dev Queues a proposal to be executed after it has succeeded.
  /// @param _proposalId The id of the proposal.
  /// @param _targets A list of target addresses for calls to be made in the proposal.
  /// @param _values A list of values (ETH) to be passed to the calls in the proposal.
  /// @param _calldatas A list of calldata for the calls in the proposal.
  /// @param _descriptionHash The hash of the description for the proposal.
  /// @return The id of the proposal.
  function _queueOperations(
    uint256 _proposalId,
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal virtual override(GovernorTimelockControlUpgradeable, GovernorUpgradeable) returns (uint48) {
    return
      GovernorTimelockControlUpgradeable._queueOperations(_proposalId, _targets, _values, _calldatas, _descriptionHash);
  }

  /// @notice Allows the owner to make calls from the governor.
  /// @dev    We want the owner to be able to upgrade settings and parameters on this Governor
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
  function relay(address target, uint256 value, bytes calldata data) external payable virtual override onlyOwner {
    Address.functionCallWithValue(target, data, value);
  }

  /// @dev returns l2 executor address; used internally for onlyGovernance check.
  /// @return address of the executor.
  function _executor()
    internal
    view
    override(GovernorTimelockControlUpgradeable, GovernorUpgradeable)
    returns (address)
  {
    return address(this);
  }

  /// @dev Executes a proposal after it has been queued.
  /// @param _proposalId The id of the proposal.
  /// @param _targets A list of target addresses for calls to be made in the proposal.
  /// @param _values A list of values (ETH) to be passed to the calls in the proposal.
  /// @param _calldatas A list of calldata for the calls in the proposal.
  /// @param _descriptionHash The hash of the description for the proposal.
  function _executeOperations(
    uint256 _proposalId,
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal virtual override(GovernorTimelockControlUpgradeable, GovernorUpgradeable) {
    return GovernorTimelockControlUpgradeable._executeOperations(
      _proposalId, _targets, _values, _calldatas, _descriptionHash
    );
  }
}
