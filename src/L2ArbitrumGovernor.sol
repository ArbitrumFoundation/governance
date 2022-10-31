// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

// CHRIS: TODO: we updated to 0.8
import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/compatibility/GovernorCompatibilityBravoUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// definition: votable token = all tokens except:
// 1. owned by arb dao
// 2. owned by foundation
// 3. airdrop not yet claimed
// 4. any tokens known to have been permanently burned

// tokens owned by the arb dao may not be voted or delegated.

// 1. snapshot for 7 days before we even hit this contract - social
// 2. proposal is made by someone with 0.1% of tokens, and they are in favour -
// 3. proposal open for 3 days before delegate snapshot is taken and voting begins
//      proposal must specify if it's constitutional change - social since we do nothing about this on chain anyway...
//      however we should represent this in the tally interface
//      proposal must specify affected chain - social
// 4. voting open for 2 weeks
// 5. require 5% for constitional change, 3% for any other
// 6. l2 waiting period - 3 days
// 7. l1 waiting period - 1 week
// 8. proposal executed

// 7 + 3 + 14 + 3 + 7 = 34 days total. Nice and slow I guess.

// 1. override proposal threshold, and work out a % for 0.1%
// 2. set votingDelay for the snapshot delay
// 3. set votingPeriod for the period that voting is allowed
// 4. need a function votableTokenSupply(), and need to use it scale the votable quorum
// in order to do this we need to really increase the denominator fidelity
// 5. set l2 timelock delay to 3 days
// 6. set l1 timelock delay to 7 days

// We need to know the number of votable tokens at the time of the snapshot
// Then we need to use the number in the calculation
// ArbGovernor needs to know about:
// 1. foundation address
// 2. dao address
// 3. airdopper address
// 4. tokens at the zero address
// 5. get total supply and subtract all of the above
// 7. then what about updating the numerator? do that every time we take a snapshot/proposal?
// 8. use this when calculating the proposalThreshold as well

// CHRIS: TODO: What is timelock conttroller vs timelockcontrollercompound?

contract L2ArbitrumGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorCompatibilityBravoUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    GovernorTimelockControlUpgradeable
{
    constructor() {
        _disableInitializers();
    }

    // TODO: should we use GovernorPreventLateQuorumUpgradeable?
    function initialize(IVotesUpgradeable _token, TimelockControllerUpgradeable _timelock) external initializer {
        // CHRIS: TODO: pass in we also should pass in these vars instead of hard coding
        __Governor_init("L2ArbitrumGovernor");
        __GovernorCompatibilityBravo_init();
        __GovernorVotes_init(_token);
        // CHRIS: TODO: set this dynamically how? we could override quorum to return our own function?
        // CHRIS: TODO: just get rid of this entirely? but we need to get quorum at a specific block height dont we? how is it used?
        __GovernorVotesQuorumFraction_init(3);
        __GovernorTimelockControl_init(_timelock);
    }

    /**
     * @notice module:user-config
     * @dev Delay, in number of block, between the proposal is created and the vote starts. This can be increassed to
     * leave time for users to buy voting power, or delegate it, before the voting of a proposal starts.
     */
    function votingDelay() public pure override returns (uint256) {
        // CHRIS: TODO: this should be specified in initializer
        return 1; // 1 block
    }

    /**
     * @notice module:user-config
     * @dev Delay, in number of blocks, between the vote start and vote ends.
     *
     * NOTE: The {votingDelay} can delay the start of the vote. This must be considered when setting the voting
     * duration compared to the voting delay.
     */
    function votingPeriod() public pure override returns (uint256) {
        // CHRIS: TODO: this should be specified in initializer, originally we had: 45_818
        return 10; // 10 blocks
    }

    // CHRIS: TODO: I dont actually think all of these need to be overriden
    // The following functions are overrides required by Solidity.

    function quorum(uint256 blockNumber)
        public
        view
        override (IGovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function state(uint256 proposalId)
        public
        view
        override (GovernorUpgradeable, IGovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (ProposalState)
    {
        return super.state(proposalId);
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
        return super.propose(targets, values, calldatas, description);
    }

    // CHRIS: TODO: consider public access to this and removing the address(0) access control on the l2 timelock
    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override (GovernorUpgradeable, GovernorTimelockControlUpgradeable) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override (GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override (GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (address)
    {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override (GovernorUpgradeable, IERC165Upgradeable, GovernorTimelockControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
