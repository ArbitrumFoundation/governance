import { RoundTripProposalCreator, L1GovConfig, UpgradeConfig } from "../src-ts/proposalCreator";
import { JsonRpcProvider } from "@ethersproject/providers";
import { DeployedContracts } from "../src-ts/types";
import fs from "fs";

import dotenv from "dotenv";
import { BigNumber, utils } from "ethers";

const goerliDeployedContracts = JSON.parse(
  fs.readFileSync("./files/goerli/deployedContracts.json").toString()
) as DeployedContracts;
const mainnetDeployedContracts = JSON.parse(
  fs.readFileSync("./files/goerli/deployedContracts.json").toString()
) as DeployedContracts;
dotenv.config();

const ensureContract = async (address: string, provider: JsonRpcProvider) => {
  if ((await provider.getCode(address)).length <= 2)
    throw new Error(`${address} contract not found`);
};

// Generate the ArbSys.sendTxToL1 arguments for a proposal whose action contract resigns on a governance chain (i.e, Arb One or Arb Goerli)
export const generateArbSysArgs = async (
  l1Provider: JsonRpcProvider,
  l2Provider: JsonRpcProvider,
  upgradeAddr: string,
  description: string,
  upgradeValue = BigNumber.from(0),
  actionIfaceStr = "function perform() external", 
  upgradeArgs = []
) => {
  let actionIface = new utils.Interface([actionIfaceStr]);
  const upgradeData = actionIface.encodeFunctionData("perform", upgradeArgs);

  const l1ChainId = (await l1Provider.getNetwork()).chainId;
  const l2ChainId = (await l2Provider.getNetwork()).chainId;

  if (!((l1ChainId === 1 && l2ChainId === 42161) || (l1ChainId === 5 && l2ChainId === 421613)))
    throw new Error("Unsupported chain pairing");

  const deployedContracts = l1ChainId === 1 ? mainnetDeployedContracts : goerliDeployedContracts;
  const { l1Timelock, l2Executor } = deployedContracts;

  await ensureContract(upgradeAddr, l2Provider);
  await ensureContract(l2Executor, l2Provider);
  await ensureContract(l1Timelock, l1Provider);

  const L1GovConfig: L1GovConfig = {
    timelockAddr: l1Timelock,
    provider: l1Provider,
  };

  const upgradeConfig: UpgradeConfig = {
    upgradeExecutorAddr: l2Executor,
    provider: l2Provider,
  };

  const proposalCreator = new RoundTripProposalCreator(L1GovConfig, upgradeConfig);
  return proposalCreator.createArbSysArgs(upgradeAddr, upgradeValue, upgradeData, description);
};
