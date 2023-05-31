## Security Council Management Contracts Deployment Steps

**a.**  Deploy `L1SecurityCouncilMgmtFactory` on L1 and execute `deployStep1`. This deploys the L1SecurityCouncilUpdateRouter and L1SecurityCouncilUpgradeExecutor contracts.

**b.**  Deploy the `L2SecurityCouncilMgmtFactory` on the governance chain and execute deployStep2. This deploys the emergencySecurityCouncilUpgradeExecutor, nonEmergencySecurityCouncilUpgradeExecutor, securityCouncilRemovalGov, and securityCouncilManager contracts (TODO: election contracts). Note that this step requires the L1SecurityCouncilUpdateRouter address deployed in **a**. 

**c.** Deploy a `SecurityCouncilUpgradeExecutor` using a `SecurityCouncilUpgradeExecutorFactory` for each security council on each DAO-governed L2 aside from the governance chain (e.g., currently on mainnet, this would be only Arbitrum Nova.) Note that the securityCouncilOwner should be set as the address alias of the L1SecurityCouncilUpdateRouter deployed in a. 

**d.** Back on L1, execute `deployStep3` on the `L1SecurityCouncilMgmtFactory`; this initializes the `L1SecurityCouncilUpdateRouter`. Note that this requires the SecurityCouncilManager address deployed in **b** as well as all SecurityCouncilUpgradeExecutor addresses deployed in **c**.