// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

/// @notice Security council members are members of one of two cohorts.
///         Periodically all the positions on a cohort are put up for election,
///         and the are members replaced with new ones.
enum Cohort {
    FIRST,
    SECOND
}

/// @notice Date struct for convenience
struct Date {
    uint256 year;
    uint256 month;
    uint256 day;
    uint256 hour;
}

error ZeroAddress();
error NotAContract(address account);
