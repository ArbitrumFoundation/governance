import {
  getProviders,
  isDistributingTokens,
  loadClaimRecipients,
  loadDaoRecipients,
  loadDeployedContracts,
  loadVestedRecipients,
} from "./providerSetup";
import {
  loadArbContracts,
  loadArbTokenDistributionContracts,
  verifyTokenDistribution,
} from "./verifiers";

async function main() {
  if (!isDistributingTokens()) {
    console.log("Token distribution mode not enabled! You can set it in .env file");
    return;
  }

  const { arbProvider, deployerConfig } = await getProviders();
  const deployedContracts = loadDeployedContracts();
  const arbContracts = loadArbContracts(arbProvider, deployedContracts);
  const distributionContracts = loadArbTokenDistributionContracts(arbProvider, deployedContracts);

  const daoRecipients = loadDaoRecipients();
  const vestedRecipients = loadVestedRecipients();
  const claimRecipients = loadClaimRecipients();

  console.log("Start verification process...");
  await verifyTokenDistribution(
    arbContracts.l2Token!,
    arbContracts.l2ArbTreasury,
    distributionContracts.l2TokenDistributor,
    distributionContracts.vestedWalletFactory,
    arbProvider,
    claimRecipients,
    daoRecipients,
    vestedRecipients,
    {
      distributorSetRecipientsEndBlock: deployedContracts.distributorSetRecipientsEndBlock!,
      distributorSetRecipientsStartBlock: deployedContracts.distributorSetRecipientsStartBlock!,
    },
    deployerConfig
  );
}

main().then(() => console.log("Verification complete."));
