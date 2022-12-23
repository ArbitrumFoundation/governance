import {
  getProviders,
  loadClaimRecipients,
  loadDaoRecipients,
  loadDeployedContracts,
  loadVestedRecipients,
} from "./providerSetup";
import { loadArbContracts, verifyTokenDistribution } from "./verifiers";

async function main() {
  const { arbProvider, deployerConfig } = await getProviders();
  const deployedContracts = loadDeployedContracts();
  const arbContracts = loadArbContracts(arbProvider, deployedContracts);

  const daoRecipients = loadDaoRecipients();
  const vestedRecipients = loadVestedRecipients();
  const claimRecipients = loadClaimRecipients();

  console.log("Start verification process...");
  await verifyTokenDistribution(
    arbContracts.l2Token!,
    arbContracts.l2ArbTreasury,
    arbContracts.l2TokenDistributor,
    arbContracts.vestedWalletFactory,
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
