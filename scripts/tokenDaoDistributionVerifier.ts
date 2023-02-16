import { getProviders, loadDaoRecipients, loadDeployedContracts } from "./providerSetup";
import { getInitialSupplyRecipientAddr, loadArbContracts, verifyDaoRecipients } from "./verifiers";

async function main() {
  const { arbProvider } = await getProviders();
  const deployedContracts = loadDeployedContracts();
  const arbContracts = loadArbContracts(arbProvider, deployedContracts);

  const daoRecipients = loadDaoRecipients();

  console.log("Start verification process...");
  
  if (!deployedContracts.l2Token) {
    throw new Error("Token not yet deployed");
  }

  const initialSupplyRecipient = await getInitialSupplyRecipientAddr(
    arbProvider,
    arbContracts.l2Token
  );

  await verifyDaoRecipients(
    initialSupplyRecipient,
    daoRecipients,
    arbContracts.l2Token!,
    arbProvider
  );
}

main().then(() => console.log("Dao allocation verification complete."));
