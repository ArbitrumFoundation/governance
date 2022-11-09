// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbitrumTimelock.sol";
import "./L2ArbitrumGovernor.sol";
import "./L2ArbitrumToken.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";

/// @title  Timelock to be used in Arbitrum governance
/// @dev    Treasury excrow; delegates its votes the exclude address

contract TreasuryGovTimelock is ArbitrumTimelock {
    constructor(address payable l2GovAddress) {
        L2ArbitrumGovernor gov = L2ArbitrumGovernor(l2GovAddress);
        IVotesUpgradeable token = IVotesUpgradeable(gov.token());
        token.delegate(gov.EXCLUDE_ADDRESS());
    }
}
