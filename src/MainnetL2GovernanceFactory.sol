import "./L2GovernanceFactory.sol";

contract MainnetL2GovernanceFactory is L2GovernanceFactory {
    function deploy(DeployCoreParams memory params)
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
        revert("ONLY_DEPLOYMAINNET");
    }

    function deployMainnet()
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
        address[] memory l2UpgradeExecutors; // DG: TODO should be security council and l1 timelock alias?

        return super.deploy(
            DeployCoreParams({
                _l2MinTimelockDelay: 42,
                _l1Token: address(42),
                _l2TokenInitialSupply: 1e10,
                _l2TokenOwner: address(42),
                _l2UpgradeExecutors: l2UpgradeExecutors,
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
