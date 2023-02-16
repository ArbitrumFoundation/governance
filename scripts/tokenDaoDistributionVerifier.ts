import { getProviders, loadDaoRecipients, loadDeployedContracts } from "./providerSetup";
import { loadArbContracts, verifyDaoRecipients } from "./verifiers";

async function main() {
  const { arbProvider, deployerConfig } = await getProviders();
  const deployedContracts = loadDeployedContracts();
  const arbContracts = loadArbContracts(arbProvider, deployedContracts);
  const daoRecipients = loadDaoRecipients();

  console.log("Start verification process...");
  
  if (!deployedContracts.l2Token) {
    throw new Error("Token not yet deployed");
  }

  await verifyDaoRecipients(
    deployerConfig.L2_ADDRESS_FOR_DAO_RECIPIENTS,
    daoRecipients,
    arbContracts.l2Token!,
    arbProvider
  );
}

main().then(() => console.log("Dao allocation verification complete."));
