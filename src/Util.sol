// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

/// @notice increments an integer without checking for overflows
/// @dev from https://github.com/ethereum/solidity/issues/11721#issuecomment-890917517
function uncheckedInc(uint256 x) pure returns (uint256) {
    unchecked {
        return x + 1;
    }
}

/// @title A token contract with governance capabilities
interface IERC20VotesUpgradeable is
    IVotesUpgradeable,
    IERC20Upgradeable,
    IERC20PermitUpgradeable
{}
