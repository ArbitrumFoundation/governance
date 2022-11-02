// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/finance/VestingWallet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./TokenDistributor.sol";
import {IERC20VotesUpgradeable} from "./Util.sol";
import "./L2ArbitrumGovernor.sol";

/// @notice Token wallet; allows claiming from airdrop, keeps tokens locked until start time and releases tokens per month until end time.
/// Allows voting and vote delegation (even while tokens are still locked).
contract L2ArbitrumVestingWallet is VestingWallet {
    using SafeMath for uint256;
    uint256 constant SECONDS_PER_MONTH = 60 * 60 * 24 * 30;
    address public immutable distributor;
    address public immutable token;
    address payable public immutable governer;

    /**
     * @param _beneficiaryAddress wallet owner
     * @param _startTimestamp  time to start vesting; set after initial cliff
     * @param _durationSeconds during over while to vest (releases per month)
     * @param _distributor token distribution contract
     * @param _token ARB token (to vest)
     * @param _governer Arbitrum L2 governer contract
     */
    constructor(
        address _beneficiaryAddress,
        uint64 _startTimestamp,
        uint64 _durationSeconds,
        address _distributor,
        address _token,
        address payable _governer
    ) VestingWallet(_beneficiaryAddress, _startTimestamp, _durationSeconds) {
        distributor = _distributor;
        token = _token;
        governer = _governer;
    }

    modifier onlyBeneficiery() {
        require(msg.sender == beneficiary(), "NOT_BENEFICIARY");
        _;
    }

    function _vestingSchedule(uint256 totalAllocation, uint64 timestamp)
        internal
        view
        override
        returns (uint256)
    {
        if (timestamp < start()) {
            return 0;
        } else if (timestamp > start() + duration()) {
            return totalAllocation;
        } else {
            uint256 vestedTimeSeconds = timestamp - start();
            uint256 vestedTimeSecondsMonthFloored = vestedTimeSeconds.sub(
                vestedTimeSeconds.mod(SECONDS_PER_MONTH)
            );
            return
                (totalAllocation * vestedTimeSecondsMonthFloored) / duration();
        }
    }

    /// @notice delegate votes to target address
    function delegate(address delegatee) public onlyBeneficiery {
        IERC20VotesUpgradeable(token).delegate(delegatee);
    }

    /// @notice claim tokens from distributor contract
    function claim() public onlyBeneficiery {
        TokenDistributor(distributor).claim();
    }

    /// @notice cast vote in governance proposal
    function castVote(uint256 proposalId, uint8 support)
        public
        onlyBeneficiery
    {
        L2ArbitrumGovernor(governer).castVote(proposalId, support);
    }
}
