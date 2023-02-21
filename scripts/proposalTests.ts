import { JsonRpcProvider } from "@ethersproject/providers";
import { parseEther } from "ethers/lib/utils";
import { wait } from "../src-ts/utils";
import {
  l2L1L2MonitoringTest,
  l2L1L2MonitoringValueTest,
  l2L1MonitoringTest,
  l2L1MonitoringValueTest,
  mineBlock,
} from "../test-ts/integration";
import { L2ArbitrumToken__factory } from "../typechain-types";
import {
  getDeployersAndConfig,
  getTeamSigner,
  isLocalDeployment,
  loadDeployedContracts,
} from "./providerSetup";
import { loadArbContracts, loadL1Contracts } from "./verifiers";

async function main() {
  const deployedContracts = loadDeployedContracts();
  const { arbDeployer, ethDeployer } = await getDeployersAndConfig();
  const arbProvider = arbDeployer.provider!;
  const ethProvider = ethDeployer.provider!;
  const teamWallet = getTeamSigner(arbProvider as JsonRpcProvider);
  const isLocal = isLocalDeployment();

  if ((await teamWallet.getBalance()).eq(0)) {
    await (
      await arbDeployer.sendTransaction({
        to: teamWallet.address,
        value: parseEther("1"),
      })
    ).wait();
  }

  if (!deployedContracts.l2Token) throw new Error("L2 token not deployed");
  const l2Token = L2ArbitrumToken__factory.connect(deployedContracts.l2Token!, teamWallet);
  if (
    (await l2Token.delegates(teamWallet.address)).toLowerCase() !== teamWallet.address.toLowerCase()
  ) {
    await (await l2Token.connect(teamWallet).delegate(teamWallet.address)).wait();
  }

  // wait at least one block has passed so that balance checkpoints are in the past
  const currentBlock = await arbProvider.getBlockNumber();
  while ((await arbProvider.getBlockNumber()) - currentBlock < 2) {
    if (isLocal) {
      await mineBlock(ethDeployer);
      await mineBlock(arbDeployer);
      await wait(1000);
    }
  }

  const arbContracts = loadArbContracts(arbProvider, deployedContracts);
  const ethContracts = loadL1Contracts(ethProvider, deployedContracts);

  console.log("L2-L1-L2 monitoring tests");
  await l2L1L2MonitoringTest(
    ethDeployer,
    arbDeployer,
    teamWallet,
    arbContracts.l2Executor,
    ethContracts.l1Timelock,
    arbContracts.l2CoreGoverner,
    isLocal
  );

  console.log("L2-L1 monitoring tests");
  await l2L1MonitoringTest(
    ethDeployer,
    arbDeployer,
    teamWallet,
    ethContracts.l1Executor,
    ethContracts.l1Timelock,
    arbContracts.l2CoreGoverner,
    isLocal
  );

  console.log("L2-L1-L2 monitoring value tests");
  await l2L1L2MonitoringValueTest(
    ethDeployer,
    arbDeployer,
    teamWallet,
    arbContracts.l2Executor,
    ethContracts.l1Timelock,
    arbContracts.l2CoreGoverner,
    isLocal
  );

  console.log("L2-L1 monitoring value tests");
  await l2L1MonitoringValueTest(
    ethDeployer,
    arbDeployer,
    teamWallet,
    ethContracts.l1Executor,
    ethContracts.l1Timelock,
    arbContracts.l2CoreGoverner,
    isLocal
  );
}

main().then(() => console.log("Tests complete."));
