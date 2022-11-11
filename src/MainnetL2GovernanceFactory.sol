import "./L2GovernanceFactory.sol";

contract MainnetL2GovernanceFactory is L2GovernanceFactory {
    function deployStep1(DeployCoreParams memory params)
        public
        override (L2GovernanceFactory)
        returns (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            L2ArbitrumGovernor treasuryGov,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor
        )
    {
        revert("MainnetL2GovernanceFactory: can only use deployStep1Mainnet");
    }

    function deployStep1Mainnet()
        public
        returns (
            L2ArbitrumToken token,
            L2ArbitrumGovernor coreGov,
            L2ArbitrumGovernor treasuryGov,
            ProxyAdmin proxyAdmin,
            UpgradeExecutor executor
        )
    {
        // TODO: update w/ actual mainnet values
        return super.deployStep1(
            DeployCoreParams({
                _l2MinTimelockDelay: 42,
                _l1Token: address(42),
                _l2TokenInitialSupply: 1e10,
                _l2TokenOwner: address(42),
                _votingPeriod: 42,
                _votingDelay: 42,
                _coreQuorumThreshold: 5,
                _treasuryQuorumThreshold: 3,
                _proposalThreshold: 5e6,
                _minPeriodAfterQuorum: 42
            })
        );
    }
}
