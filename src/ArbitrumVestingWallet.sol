// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/finance/VestingWallet.sol";
import "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";

import "./TokenDistributor.sol";
import {IERC20VotesUpgradeable} from "./Util.sol";

/// @notice A wallet that vests tokens over time. The full token allowance can be used for delegating
///         and voting immediately.
/// @dev    Tokens can be claimed to this contract from a token distributor. The full token allowance
///         is then immediately eligible for voting and delegation. A quarter of the tokens vest
///         immediately on the start date, after that they vest proportionally each month
contract ArbitrumVestingWallet is VestingWallet {
    uint256 constant SECONDS_PER_MONTH = (60 * 60 * 24 * 365) / 12;

    /// @param _beneficiaryAddress Wallet owner
    /// @param _startTimestamp The time to start vesting; at this point a quarter of the assets will immediately vest
    /// @param _durationSeconds The time period for the remaining tokens to full vest
    constructor(address _beneficiaryAddress, uint64 _startTimestamp, uint64 _durationSeconds)
        VestingWallet(_beneficiaryAddress, _startTimestamp, _durationSeconds)
    {}

    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary(), "ArbitrumVestingWallet: not beneficiary");
        _;
    }

    function _vestingSchedule(uint256 totalAllocation, uint64 timestamp)
        internal
        view
        override
        returns (uint256)
    {
        // at the start date a quarter of the assets immediately vest
        // after they vest proportionally each month for the duration

        if (timestamp < start()) {
            return 0;
        } else if (timestamp > start() + duration()) {
            return totalAllocation;
        } else {
            // a quarter of the tokens vest on the start data
            uint256 cliff = totalAllocation / 4;

            // we vest in units of months, so remove any seconds over the end of the last month
            uint256 vestedTimeSeconds = timestamp - start();
            uint256 vestedTimeSecondsMonthFloored =
                vestedTimeSeconds - (vestedTimeSeconds % SECONDS_PER_MONTH);
            uint256 remaining =
                ((totalAllocation - cliff) * (vestedTimeSecondsMonthFloored)) / duration();

            return cliff + remaining;
        }
    }

    /// @notice Delegate votes to target address
    function delegate(address token, address delegatee) public onlyBeneficiary {
        IERC20VotesUpgradeable(token).delegate(delegatee);
    }

    /// @notice Claim tokens from a distributor contract
    function claim(address distributor) public onlyBeneficiary {
        TokenDistributor(distributor).claim();
    }

    /// @notice Cast vote in a governance proposal
    function castVote(address governor, uint256 proposalId, uint8 support) public onlyBeneficiary {
        IGovernorUpgradeable(governor).castVote(proposalId, support);
    }

    // @notice release vested tokens; only benefiary can call so VestingWallet retains voting power
    function release(address token) public override onlyBeneficiary {
        super.release(token);
    }
}
