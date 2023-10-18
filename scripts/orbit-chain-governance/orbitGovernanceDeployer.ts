import { Wallet, ethers } from "ethers";
import {
  GovernanceChainGovFactory__factory,
  ParentChainGovFactory__factory,
  WrappedNativeGovToken__factory,
} from "../../typechain-types";
import { JsonRpcProvider } from "@ethersproject/providers";
import { execSync } from "child_process";

import dotenv from "dotenv";
dotenv.config();

export const deployGovernance = async () => {
  // load env vars
  const parentChainRpc = process.env["PARENT_CHAIN_RPC"] as string;
  const parentChainDeployKey = process.env["PARENT_CHAIN_DEPLOY_KEY"] as string;
  const childChainRpc = process.env["CHILD_CHAIN_RPC"] as string;
  const childChainDeployKey = process.env["CHILD_CHAIN_DEPLOY_KEY"] as string;
  if (![parentChainRpc, parentChainDeployKey, childChainRpc, childChainDeployKey].every(Boolean)) {
    throw new Error(
      "Following env vars have to be set: PARENT_CHAIN_RPC, PARENT_CHAIN_DEPLOY_KEY, CHILD_CHAIN_RPC, CHILD_CHAIN_DEPLOY_KEY"
    );
  }

  // deploy parent chain governance factory
  const parentChainDeployerWallet = new Wallet(parentChainDeployKey).connect(
    new JsonRpcProvider(parentChainRpc)
  );
  const parentChainFactoryFac = await new ParentChainGovFactory__factory(
    parentChainDeployerWallet
  ).deploy();
  const parentChainFactory = await parentChainFactoryFac.deployed();
  console.log("ParentChainGovFactory: ", parentChainFactory.address);

  // deploy child chain governance factory
  const childChainDeployerWallet = new Wallet(childChainDeployKey).connect(
    new JsonRpcProvider(childChainRpc)
  );
  const childChainFactoryFac = await new GovernanceChainGovFactory__factory(
    childChainDeployerWallet
  ).deploy();
  const childChainFactory = await childChainFactoryFac.deployed();
  console.log("GovernanceChainGov: ", childChainFactory.address);

  // deploy governance token
  const governanceTokenFac = await new WrappedNativeGovToken__factory(
    childChainDeployerWallet
  ).deploy();
  const governanceToken = await governanceTokenFac.deployed();

  // get deployment data
  const rollupData = await getDeploymentData();

  /// step1
  await (
    await childChainFactory.deployStep1({
      _governanceToken: governanceToken.address,
      _govChainUpExec: governanceToken.address, // TODO set proper address
      _govChainProxyAdmin: governanceToken.address, // TODO set proper address
      _proposalThreshold: 100,
      _votingPeriod: 10,
      _votingDelay: 10,
      _minTimelockDelay: 7,
      _minPeriodAfterQuorum: 1,
      _coreQuorumThreshold: 500,
    })
  ).wait();
};

async function getDeploymentData() {
  let sequencerContainer = execSync('docker ps --filter "name=l3node" --format "{{.Names}}"')
    .toString()
    .trim();

  const deploymentData = execSync(
    `docker exec ${sequencerContainer} cat /config/l3deployment.json`
  ).toString();

  const parsedDeploymentData = JSON.parse(deploymentData) as {
    bridge: string;
    inbox: string;
    ["sequencer-inbox"]: string;
    rollup: string;
    ["native-token"]: string;
    ["upgrade-executor"]: string;
  };

  return parsedDeploymentData;
}

async function main() {
  console.log("Start governance deployment process...");
  await deployGovernance();
  console.log("Deployment finished!");
}

main().then(() => console.log("Done."));
