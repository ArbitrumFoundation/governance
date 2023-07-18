// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../L2ArbitrumGovernor.sol";
import "./../interfaces/ISecurityCouncilManager.sol";
import "../../Util.sol";
import "../Common.sol";

contract SecurityCouncilMemberRemovalGovernor is L2ArbitrumGovernor {
    uint256 public constant voteSuccessDenominator = 10_000;

    uint256 public voteSuccessNumerator;

    ISecurityCouncilManager public securityCouncilManager;

    event VoteSuccessNumeratorSet(uint256 indexed voteSuccessNumerator);
    event MemberRemovalProposed(address memberToRemove, string description);

    error InvalidOperationsLength();
    error TargetNotManager(address target);
    error ValueNotZero(uint256 value);
    error UnexpectedCalldataLength();
    error CallNotRemoveMember(bytes4 selector);
    error MemberNotFound(address memberToRemove);
    error AbstainDisallowed();
    error InvalidVoteSuccessNumerator(uint256 voteSuccessNumerator);

    /// @notice Initialize the contract
    /// @dev this method does not include an initializer modifier; it calls its parent's initiaze method which itself prevents repeated initialize calls
    /// @param _voteSuccessNumerator value that with denominator 10_000 determines the ration of for/against votes required for success
    /// @param _securityCouncilManager security council manager contract
    /// @param _token The address of the governance token
    /// @param _timelock A time lock for proposal execution
    /// @param _owner The DAO (Upgrade Executor); admin over proposal role
    /// @param _votingDelay The delay between a proposal submission and voting starts
    /// @param _votingPeriod The period for which the vote lasts
    /// @param _quorumNumerator The proportion of the circulating supply required to reach a quorum
    /// @param _proposalThreshold The number of delegated votes required to create a proposal
    /// @param _minPeriodAfterQuorum The minimum number of blocks available for voting after the quorum is reached
    function initialize(
        uint256 _voteSuccessNumerator,
        ISecurityCouncilManager _securityCouncilManager,
        IVotesUpgradeable _token,
        TimelockControllerUpgradeable _timelock,
        address _owner,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumNumerator,
        uint256 _proposalThreshold,
        uint64 _minPeriodAfterQuorum
    ) public {
        if (!Address.isContract(address(_securityCouncilManager))) {
            revert NotAContract(address(_securityCouncilManager));
        }
        securityCouncilManager = _securityCouncilManager;
        _setVoteSuccessNumerator(_voteSuccessNumerator);
        this.initialize(
            _token,
            _timelock,
            _owner,
            _votingDelay,
            _votingPeriod,
            _quorumNumerator,
            _proposalThreshold,
            _minPeriodAfterQuorum
        );
    }

    /// @notice Assumes the passed in bytes is an abi encoded function call, and splits into the selector and the rest
    /// @param calldataWithSelector The call data to split
    /// @return The selector
    /// @return The rest of the function call data
    function separateSelector(bytes calldata calldataWithSelector)
        external
        pure
        returns (bytes4, bytes memory)
    {
        bytes4 selector = bytes4(calldataWithSelector[:4]);
        bytes memory rest = calldataWithSelector[4:];
        return (selector, rest);
    }

    /// @notice Propose a security council member removal. Method conforms to the governor propose interface but enforces that only calls to removeMember can be propsoed.
    /// @param targets Target contract operation; must be [securityCouncilManager]
    /// @param values Value for removeMmeber; must be [0]
    /// @param calldatas Operation calldata; must be removeMember with address argument
    /// @param description rationale for member removal
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(GovernorUpgradeable, IGovernorUpgradeable) returns (uint256) {
        if (targets.length != 1) {
            revert InvalidOperationsLength();
        }
        // length equality of targets, values, and calldatas is checked in  GovernorUpgradeable.propose

        if (targets[0] != address(securityCouncilManager)) {
            revert TargetNotManager(targets[0]);
        }
        if (values[0] != 0) {
            revert ValueNotZero(values[0]);
        }
        if (calldatas[0].length != 36) {
            revert UnexpectedCalldataLength();
        }

        (bytes4 selector, bytes memory rest) = this.separateSelector(calldatas[0]);
        address memberToRemove = abi.decode(rest, (address));

        if (selector != ISecurityCouncilManager.removeMember.selector) {
            revert CallNotRemoveMember(selector);
        }
        if (
            !securityCouncilManager.firstCohortIncludes(memberToRemove)
                && !securityCouncilManager.secondCohortIncludes(memberToRemove)
        ) {
            revert MemberNotFound(memberToRemove);
        }

        emit MemberRemovalProposed(memberToRemove, description);
        return GovernorUpgradeable.propose(targets, values, calldatas, description);
    }

    /// @notice override to allow for required vote success ratio that isn't 0.5
    /// @param proposalId target proposal id
    function _voteSucceeded(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorCountingSimpleUpgradeable, GovernorUpgradeable)
        returns (bool)
    {
        (uint256 againstVotes, uint256 forVotes,) = proposalVotes(proposalId);

        // for-votes / total-votes  >  success-numerator/ success-denominator
        return voteSuccessDenominator * forVotes > (forVotes + againstVotes) * voteSuccessNumerator;
    }

    ///@notice A removal proposal if a theshold of all cast votes vote in favor of removal. Thus, abstaining would be exactly equivalent to voting against. Thus, to prevent any confusing, abstaining is disallowed.
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory params
    ) internal virtual override(GovernorCountingSimpleUpgradeable, GovernorUpgradeable) {
        // TODO: confirm / finalize this decision
        if (VoteType(support) == VoteType.Abstain) {
            revert AbstainDisallowed();
        }
        GovernorCountingSimpleUpgradeable._countVote(proposalId, account, support, weight, params);
    }

    /// @notice set numerator for removal vote to succeed; only DAO can call
    /// @param _voteSuccessNumerator new numberator value
    function setVoteSuccessNumerator(uint256 _voteSuccessNumerator) public onlyOwner {
        _setVoteSuccessNumerator(_voteSuccessNumerator);
    }

    function _setVoteSuccessNumerator(uint256 _voteSuccessNumerator) internal {
        if (!(0 < _voteSuccessNumerator && _voteSuccessNumerator <= voteSuccessDenominator)) {
            revert InvalidVoteSuccessNumerator(_voteSuccessNumerator);
        }
        voteSuccessNumerator = _voteSuccessNumerator;
        emit VoteSuccessNumeratorSet(_voteSuccessNumerator);
    }
}
