import {
  fullTokenVerify,
  getProviders,
  loadClaimRecipients,
  loadDeployedContracts,
  loadVestedRecipients,
} from "./providerSetup";
import { assertEquals } from "./testUtils";
import {
  loadArbContracts,
  loadArbTokenDistributionContracts,
  verifyL2TokenDistributorEnd,
  verifyL2TokenDistributorStart,
  verifyTokenDistribution,
} from "./verifiers";

async function main() {
  const { arbProvider, deployerConfig } = await getProviders();
  const deployedContracts = loadDeployedContracts();
  const arbContracts = loadArbContracts(arbProvider, deployedContracts);
  const distributionContracts = loadArbTokenDistributionContracts(arbProvider, deployedContracts);

  const vestedRecipients = loadVestedRecipients();
  const claimRecipients = loadClaimRecipients();

  console.log(`Start ${fullTokenVerify() ? "full" : "partial"} verification process...`);
  await verifyTokenDistribution(
    arbContracts.l2Token!,
    arbContracts.l2ArbTreasury,
    distributionContracts.l2TokenDistributor,
    distributionContracts.vestedWalletFactory,
    arbProvider,
    claimRecipients,
    vestedRecipients,

    deployerConfig
  );

  await verifyL2TokenDistributorStart(
    distributionContracts.l2TokenDistributor,
    arbContracts.l2Token,
    arbContracts.l2Executor,
    arbContracts.l2CoreGoverner,
    arbProvider,
    claimRecipients,
    deployerConfig
  );

  if (fullTokenVerify()) {
    console.log("Verifying token claimants...");
    await verifyL2TokenDistributorEnd(
      distributionContracts.l2TokenDistributor,
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
