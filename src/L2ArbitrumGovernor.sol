// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

// CHRIS: TODO: we updated to 0.8
import "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/compatibility/GovernorCompatibilityBravoUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./L2ArbitrumToken.sol";

// definition: votable token = all tokens except:
// 1. owned by arb dao
// 2. owned by foundation
// 3. airdrop not yet claimed
// 4. any tokens known to have been permanently burned
// 5. tokens that have been sent to the unclaimedTokenReceiver from the token distributor

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
    GovernorTimelockControlUpgradeable
{
    uint256 votingPeriod_;
    uint256 votingDelay_;
    /// @notice Addresses to exclude from circulating votes for quorum threshold calculation. 
    address[] public circulatingVotesExcludeList;
    /// @notice Addresses to exclude from circulating votes for quorum threshold calculation. 
    mapping(address => bool) public circulatingVotesExcludeMap;
    constructor() {
        _disableInitializers();
    }

    // TODO: should we use GovernorPreventLateQuorumUpgradeable?
    function initialize(IVotesUpgradeable _token, TimelockControllerUpgradeable _timelock, uint256 _votingPeriod, uint256 _votingDelay, address[] memory _circulatingVotesExcludeList) external initializer {
        // CHRIS: TODO: pass in we also should pass in these vars instead of hard coding
        __Governor_init("L2ArbitrumGovernor");
        __GovernorCompatibilityBravo_init();
        __GovernorVotes_init(_token);
        // CHRIS: TODO: set this dynamically how? we could override quorum to return our own function?
        // CHRIS: TODO: just get rid of this entirely? but we need to get quorum at a specific block height dont we? how is it used?
        __GovernorTimelockControl_init(_timelock);
        votingDelay_ = _votingDelay;
        votingPeriod_ = _votingPeriod;
        circulatingVotesExcludeList = _circulatingVotesExcludeList;
        for (uint256 i = 0; i < _circulatingVotesExcludeList.length; i++) {
            circulatingVotesExcludeMap[_circulatingVotesExcludeList[i]] = true;
        }
    }

    /**
     * @notice module:user-config
     * @dev Delay, in number of block, between the proposal is created and the vote starts. This can be increassed to
     * leave time for users to buy voting power, or delegate it, before the voting of a proposal starts.
     */
    function votingDelay() public view override returns (uint256) {
        return votingDelay_;
    }

    /**
     * @notice module:user-config
     * @dev Delay, in number of blocks, between the vote start and vote ends.
     *
     * NOTE: The {votingDelay} can delay the start of the vote. This must be considered when setting the voting
     * duration compared to the voting delay.
     */
    function votingPeriod() public view override returns (uint256) {
        return votingPeriod_;
    }

    /// @notice Updates addresses to exlude from circulating votes supply for quorum threshold calculation.
    // TODO: Access Control 
    function addToCirculatingVotesExcludeList(address addressToExclude) external {
        require(!circulatingVotesExcludeMap[addressToExclude], "already excluded");
        circulatingVotesExcludeList.push(addressToExclude);
        circulatingVotesExcludeMap[addressToExclude] = true;
    }

        /// @notice Get "circulating" votes supply; i.e., total minus excluded addresses.
    function getPastCirculatingSupply(uint256 blockNumber) public view virtual returns (uint256) {
        uint256 supply = token.getPastTotalSupply(blockNumber);
        for (uint256 index = 0; index < circulatingVotesExcludeList.length; index++) {
            supply -= token.getPastVotes(circulatingVotesExcludeList[index], blockNumber);
        }
        return supply;
    }


    function quorum(uint256 blockNumber)
        public
        view
        override (IGovernorUpgradeable)
        returns (uint256)
    {
        return getPastCirculatingSupply(blockNumber) * 3 / 100;
    }

    /// @notice cast vote on proposal; restrict access from exclude list
    function castVote(uint256 proposalId, uint8 support)
        public 
        override(GovernorUpgradeable, IGovernorUpgradeable)
        returns (uint256) 
    {
        require(!circulatingVotesExcludeMap[msg.sender], "CAN'T VOTE");
        super.castVote(proposalId, support);
    }

    // CHRIS: TODO: I dont actually think all of these need to be overriden
    // The following functions are overrides required by Solidity.

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
