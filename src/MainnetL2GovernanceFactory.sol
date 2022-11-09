import "./L2GovernanceFactory.sol";

// TODO: add mainnet values
contract MainnetL2GovernanceFactory is L2GovernanceFactory {
    address[] l2UpgradeExecutors = [address(42), address(43)]; // DG: TODO should be security council and l1 timelock alias?

    constructor()
        L2GovernanceFactory(
            ConstructorParams({
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
        )
    {}
}
