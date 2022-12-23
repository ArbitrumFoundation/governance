import { getProviders } from "./providerSetup";
import { loadArbContracts, verifyTokenDistribution } from "./verifiers";

async function main() {
  const { arbProvider, deployerConfig } = await getProviders();
  const arbContracts = loadArbContracts(arbProvider);

  console.log("Start verification process...");
  await verifyTokenDistribution(
    arbContracts.l2Token,
    arbContracts.l2ArbTreasury,
    arbContracts.l2TokenDistributor,
    arbContracts.vestedWalletFactory,
    arbProvider,
    deployerConfig
  );
}

main().then(() => console.log("Done."));
