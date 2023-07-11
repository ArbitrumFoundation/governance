// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

/// @notice Security councils members are members of one of two cohorts.
///         Periodically all the positions on a cohort are put up for election,
///         and the members replaced with new ones.
enum Cohort {
    FIRST,
    SECOND
}

error ZeroAddress();
error NotAContract(address account);

