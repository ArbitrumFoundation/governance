import { ContractVerifier } from "./contractVerifier";
import {
  DeployProgressCache,
  getDeployersAndConfig,
  isDeployingToNova,
  loadDeployedContracts,
} from "./providerSetup";

export const envVars = {
  arbApiKey: process.env["ARBISCAN_API_KEY"] as string,
  ethApiKey: process.env["ETHERSCAN_API_KEY"] as string,
  novaApiKey: process.env["NOVA_ARBISCAN_API_KEY"] as string,
  arbDeployer: process.env["ARB_DEPLOYER"] as string,
};

const checkEnvVars = (conf: typeof envVars) => {
  if (conf.arbApiKey == undefined) throw new Error("Missing ARBISCAN_API_KEY in env vars");
  if (conf.ethApiKey == undefined) throw new Error("Missing ETHERSCAN_API_KEY in env vars");
  if (isDeployingToNova()) {
    if (conf.novaApiKey == undefined) throw new Error("Missing NOVA_ARBISCAN_API_KEY in env vars");
  }
  if (conf.arbDeployer == undefined) throw new Error("Missing ARB_DEPLOYER in env vars");
};

async function main() {
  console.log("Start verifying contracts...");

  checkEnvVars(envVars);
  const { arbNetwork, novaNetwork, deployerConfig } = await getDeployersAndConfig();
  const deployedContracts: DeployProgressCache = loadDeployedContracts();

  const arbVerifier = new ContractVerifier(
    arbNetwork.chainID,
    envVars.arbApiKey,
    deployedContracts
  );
  await arbVerifier.verifyArbContracts(deployerConfig, envVars.arbDeployer);

  const ethVerifier = new ContractVerifier(
    arbNetwork.partnerChainID,
    envVars.ethApiKey,
    deployedContracts
  );
  await ethVerifier.verifyEthContracts();

  if (isDeployingToNova()) {
    const novaVerifier = new ContractVerifier(
      novaNetwork!.chainID,
      envVars.novaApiKey,
      deployedContracts
    );
    await novaVerifier.verifyNovaContracts();
  }
}

main().then(() => console.log("Done."));
