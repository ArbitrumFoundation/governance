// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbitrumTimelock.sol";
import "./L2ArbitrumGovernor.sol";
import "./L2ArbitrumToken.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";

// DG: TODO
/// @title  Timelock to be used in Arbitrum governance
/// @dev    This contract adds no other functionality to the TimelockControllerUpgradeable
///         other than the ability to initialize it. TimelockControllerUpgradeable has not
///         public methods for this
contract TreasuryGovTimelock is ArbitrumTimelock {
    constructor(address payable l2GovAddress) {
        L2ArbitrumGovernor gov = L2ArbitrumGovernor(l2GovAddress);
        IVotesUpgradeable token = IVotesUpgradeable(gov.token());
        token.delegate(gov.EXCLUDE_ADDRESS());
    }
}
