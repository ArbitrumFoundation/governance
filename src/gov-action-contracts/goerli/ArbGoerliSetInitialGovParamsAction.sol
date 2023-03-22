// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistryInterfaces.sol";

contract ArbGoerliSetInitialGovParamsAction {
    uint256 public constant coreVotingDelay = 10;
    uint256 public constant coreVotingPeriod = 50;
    uint256 public constant coreTimelockPeriod = 900; // seconds
    uint256 public constant treasuryVotingDelay = 10;
    uint256 public constant treasuryVotingPeriod = 50;
    uint256 public constant treasuryTimelockPeriod = 900; // seconds
    IL2AddressRegistry immutable registry;

    constructor(IL2AddressRegistry _registry) {
        registry = _registry;
    }

    function setParams(
        IL2ArbitrumGoverner gov,
        IArbitrumTimelock timelock,
        uint256 vd,
        uint256 vp,
        uint256 tp
    ) internal {
        bytes memory votingDelayData =
            abi.encodeWithSelector(IL2ArbitrumGoverner.setVotingDelay.selector, vd);
        gov.relay(address(gov), 0, votingDelayData);
        require(gov.votingDelay() == vd, "ArbGoerliSetInitialGovParamsAction: Voting delay not set");

        bytes memory votingPeriodData =
            abi.encodeWithSelector(IL2ArbitrumGoverner.setVotingPeriod.selector, vp);
        gov.relay(address(gov), 0, votingPeriodData);
        require(
            gov.votingPeriod() == vp, "ArbGoerliSetInitialGovParamsAction: Voting period not set"
        );

        timelock.updateDelay(tp);
        require(timelock.getMinDelay() == tp, "ArbGoerliSetInitialGovParamsAction: Timelock delay");
    }

    function perform() external {
        setParams(
            registry.coreGov(),
            registry.coreGovTimelock(),
            coreVotingDelay,
            coreVotingPeriod,
            coreTimelockPeriod
        );
        setParams(
            registry.treasuryGov(),
            registry.treasuryGovTimelock(),
            treasuryVotingDelay,
            treasuryVotingPeriod,
            treasuryTimelockPeriod
        );
    }
}
