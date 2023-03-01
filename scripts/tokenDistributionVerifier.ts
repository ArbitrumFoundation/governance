import {
  fullTokenVerify,
  getProviders,
  loadClaimRecipients,
  loadDeployedContracts,
} from "./providerSetup";
import { assertEquals } from "./testUtils";
import {
  loadArbContracts,
  verifyL2TokenDistributorEnd,
  verifyTokenDistribution,
  loadArbTokenDistributor,
  verifyL2TokenDistributorStart,
} from "./verifiers";

async function main() {
  const { arbProvider, deployerConfig } = await getProviders();
  const deployedContracts = loadDeployedContracts();
  const arbContracts = loadArbContracts(arbProvider, deployedContracts);
  const l2TokenDistributor = loadArbTokenDistributor(arbProvider, deployedContracts);

  const claimRecipients = loadClaimRecipients();

  console.log(`Start ${fullTokenVerify() ? "full" : "partial"} verification process...`);
  await verifyTokenDistribution(
    arbContracts.l2Token!,
    arbContracts.l2ArbTreasury,
    l2TokenDistributor,
    arbProvider,
    claimRecipients,
    deployerConfig
  );

  await verifyL2TokenDistributorStart(
    l2TokenDistributor,
    arbContracts.l2Token,
    arbContracts.l2CoreGoverner,
    arbProvider,
    claimRecipients,
    deployerConfig
  );

  if (fullTokenVerify()) {
    console.log("Verifying token claimants...");
    await verifyL2TokenDistributorEnd(
      l2TokenDistributor,
      arbContracts.l2Executor,
      claimRecipients,
      {
        distributorSetRecipientsEndBlock: deployedContracts.distributorSetRecipientsEndBlock!,
        distributorSetRecipientsStartBlock: deployedContracts.distributorSetRecipientsStartBlock!,
      },
      deployerConfig
    );

    assertEquals(
      await arbContracts.l2Token.owner(),
      arbContracts.l2Executor.address,
      "L2UpgradeExecutor should be L2ArbitrumToken's owner"
    );
  }
}

main().then(() => console.log("Verification complete."));
