import {
  l2L1L2MonitoringTest,
  l2L1L2MonitoringValueTest,
  l2L1MonitoringTest,
  l2L1MonitoringValueTest,
} from "../test-ts/integration";
import { getDeployersAndConfig, getProviders, loadDeployedContracts } from "./providerSetup";
import { loadArbContracts, loadL1Contracts } from "./verifiers";

async function main() {
  const { arbProvider, ethProvider } = await getProviders();
  const deployedContracts = loadDeployedContracts();
  const { arbDeployer, ethDeployer } = await getDeployersAndConfig();

  const arbContracts = loadArbContracts(arbProvider, deployedContracts);
  const ethContracts = loadL1Contracts(ethProvider, deployedContracts);

  console.log("L2-L1-L2 monitoring tests");
  await l2L1L2MonitoringTest(
    ethDeployer,
    arbDeployer,
    ethDeployer,
    arbDeployer,
    arbContracts.l2Executor,
    ethContracts.l1Timelock,
    arbContracts.l2CoreGoverner
  );

  console.log("L2-L1 monitoring tests");
  await l2L1MonitoringTest(
    ethDeployer,
    arbDeployer,
    ethDeployer,
    arbDeployer,
    ethContracts.l1Executor,
    ethContracts.l1Timelock,
    arbContracts.l2CoreGoverner
  );

  console.log("L2-L1-L2 monitoring value tests");
  await l2L1L2MonitoringValueTest(
    ethDeployer,
    arbDeployer,
    ethDeployer,
    arbDeployer,
    arbContracts.l2Executor,
    ethContracts.l1Timelock,
    arbContracts.l2CoreGoverner
  );

  console.log("L2-L1 monitoring value tests");
  await l2L1MonitoringValueTest(
    ethDeployer,
    arbDeployer,
    ethDeployer,
    arbDeployer,
    ethContracts.l1Executor,
    ethContracts.l1Timelock,
    arbContracts.l2CoreGoverner
  );
}

main().then(() => console.log("Tests complete."));
