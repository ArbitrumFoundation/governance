## Orbit Chain Governance Deployment

The Orbit Chain Governance Deployment factories deploy a cross chain governance system; proposal creation and voting takes place on an Orbit chain referred to as the "governance chain," which serves to govern contracts both on the governance chain and its parent chain via cross chain messages.

This deployment is comparable to the one carried by the `L2GovernanceFactory` / `L1GovernanceFactory` contracts, except the Orbit deployment excludes certain contracts prupose-specific to the Arbitrum DAO (e.g., the DAO treasury). For info on the DAO's governance deployment, see [Arbitrum DAO Governance](../../docs/overview.md).


### Steps
0. Prior to Orbit Governance deployment, the following contracts should already be deployed:
    - Governance chain:
        - Governance ERC20 Token that implements the Open Zeppelin `IVotesUpgradeable` interface.
        - `UpgradeExecutor`
        - `ProxyAdmin`
    - Parent chain:
        - `UpgradeExecutor`
        - `ProxyAdmin`
1. Deploy `GovernanceChainGovFactory`` and execute `deployStep1`
2. Deploy `ParentChainGovFactory` and execute `deployStep2`; requires address of timelock on deployed in `GovernanceChainGovFactory` 
3. Grant `EXECUTOR_ROLE` affordance on the parent chain `UpgradeExecutor` to the governance timelock on the parent chain. Grant `EXECUTOR_ROLE` affordance on the governance chain `UpgradeExecutor` to the [address-alias](https://docs.arbitrum.io/arbos/l1-to-l2-messaging#address-aliasing) of the governance timelock on the parent chain.

Optional:
1. Additional execution affordances can be given by granting the `EXECUTOR_ROLE` to additional contracts on the `UpradeExecutor`s; e.g., a multisig that can bypass voting and delays to make emergency upgrades (a la the Arbitrum DAO Security Council).
1. Other `EXECUTOR_ROLE` affordances that were granted the UpgradeExecutor prior to deployment to facilitate the deployment process can now be removed.
