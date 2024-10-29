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
import { Signer, Wallet } from "ethers";

const createAndFundWallet = async (funder: Signer) => {
  const randWallet = Wallet.createRandom().connect(funder.provider!);
  await (
    await funder.sendTransaction({
      to: randWallet.address,
      value: parseEther("0.1"),
    })
  ).wait();
  return randWallet;
};

async function main() {
  const deployedContracts = loadDeployedContracts();
  const { arbDeployer, ethDeployer } = await getDeployersAndConfig();
  const arbProvider = arbDeployer.provider!;
  const ethProvider = ethDeployer.provider!;
  const teamWallet = getTeamSigner(arbProvider as JsonRpcProvider);
  const isLocal = isLocalDeployment();

  if ((await teamWallet.getBalance()).lt(parseEther("0.5"))) {
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
      await mineBlock(ethDeployer, "2blocketh");
      await mineBlock(arbDeployer, "2blockarb");
    }
    await wait(1000);
  }

  const arbContracts = loadArbContracts(arbProvider, deployedContracts);
  const ethContracts = loadL1Contracts(ethProvider, deployedContracts);

  // create some random accounts to do the testing on, we do this so because we want
  // to run the tests in parallel, but dont want them to get mixed up nonces by trying
  // to send at the same time. So instead we run the tests with different keys

  console.log("Sending funds to local wallets 1")
  const l1Wallet1 = await createAndFundWallet(ethDeployer);
  const l2Wallet1 = await createAndFundWallet(arbDeployer);
  let localMining: { l1Signer: Signer; l2Signer: Signer } | undefined = undefined;

  if (isLocal) {
    localMining = {
      l1Signer: await createAndFundWallet(ethDeployer),
      l2Signer: await createAndFundWallet(arbDeployer),
    };
  }

  console.log("Sending funds to local wallets 2")
  const l1Wallet2 = await createAndFundWallet(ethDeployer);
  const l2Wallet2 = await createAndFundWallet(arbDeployer);

  let localMining2: { l1Signer: Signer; l2Signer: Signer } | undefined = undefined;
  if (isLocal) {
    localMining2 = {
      l1Signer: await createAndFundWallet(ethDeployer),
      l2Signer: await createAndFundWallet(arbDeployer),
    };
  }

  console.log("Sending funds to local wallets 3")
  const l1Wallet3 = await createAndFundWallet(ethDeployer);
  const l2Wallet3 = await createAndFundWallet(arbDeployer);

  let localMining3: { l1Signer: Signer; l2Signer: Signer } | undefined = undefined;
  if (isLocal) {
    localMining3 = {
      l1Signer: await createAndFundWallet(ethDeployer),
      l2Signer: await createAndFundWallet(arbDeployer),
    };
  }

  console.log("Sending funds to local wallets 4")
  const l1Wallet4 = await createAndFundWallet(ethDeployer);
  const l2Wallet4 = await createAndFundWallet(arbDeployer);

  let localMining4: { l1Signer: Signer; l2Signer: Signer } | undefined = undefined;
  if (isLocal) {
    localMining4 = {
      l1Signer: await createAndFundWallet(ethDeployer),
      l2Signer: await createAndFundWallet(arbDeployer),
    };
  }

  console.log("L2-L1-L2 monitoring tests");
  const test1 = l2L1L2MonitoringTest(
    l1Wallet1,
    l2Wallet1,
    teamWallet,
    arbContracts.l2Executor,
    ethContracts.l1Timelock,
    arbContracts.l2CoreGoverner,
    localMining
  );

  // wait a little for the proposal to actually be made and the votes cast
  // on goerli the voting delay is 2 blocks, so we should have cast the vote after 60 sec
  await wait(60000);

  console.log("L2-L1 monitoring tests");
  const test2 = l2L1MonitoringTest(
    l1Wallet2,
    l2Wallet2,
    teamWallet,
    ethContracts.l1Executor,
    ethContracts.l1Timelock,
    arbContracts.l2CoreGoverner,
    localMining2
  );

  await wait(60000);

  console.log("L2-L1-L2 monitoring value tests");
  const test3 = l2L1L2MonitoringValueTest(
    l1Wallet3,
    l2Wallet3,
    teamWallet,
    arbContracts.l2Executor,
    ethContracts.l1Timelock,
    arbContracts.l2CoreGoverner,
    localMining3
  );

  await wait(60000);

  console.log("L2-L1 monitoring value tests");
  const test4 = l2L1MonitoringValueTest(
    l1Wallet4,
    l2Wallet4,
    teamWallet,
    ethContracts.l1Executor,
    ethContracts.l1Timelock,
    arbContracts.l2CoreGoverner,
    localMining4
  );

  await Promise.all([test1, test2, test3, test4]);

  await wait(1000);
}

main().then(() => console.log("Tests complete."));
