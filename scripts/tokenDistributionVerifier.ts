import { getProviders, loadClaimRecipients, loadDeployedContracts } from "./providerSetup";
import { assertEquals } from "./testUtils";
import {
  loadArbContracts,
  loadArbTokenDistributor,
  verifyL2TokenDistributor,
  verifyTokenDistribution,
} from "./verifiers";

async function main() {
  const { arbProvider, deployerConfig } = await getProviders();
  const deployedContracts = loadDeployedContracts();
  const arbContracts = loadArbContracts(arbProvider, deployedContracts);
  const l2TokenDistributor = loadArbTokenDistributor(arbProvider, deployedContracts);

  const claimRecipients = loadClaimRecipients();

  console.log("Start verification process...");
  await verifyTokenDistribution(
    arbContracts.l2Token!,
    arbContracts.l2ArbTreasury,
    l2TokenDistributor,
    arbProvider,
    claimRecipients,
    {
      distributorSetRecipientsEndBlock: deployedContracts.distributorSetRecipientsEndBlock!,
      distributorSetRecipientsStartBlock: deployedContracts.distributorSetRecipientsStartBlock!,
    },
    deployerConfig
  );

  await verifyL2TokenDistributor(
    l2TokenDistributor,
    arbContracts.l2Token,
    arbContracts.l2Executor,
    arbContracts.l2CoreGoverner,
    arbProvider,
    claimRecipients,
    deployerConfig
  );

  assertEquals(
    await arbContracts.l2Token.owner(),
    arbContracts.l2Executor.address,
    "L2UpgradeExecutor should be L2ArbitrumToken's owner"
  );
}

main().then(() => console.log("Verification complete."));
