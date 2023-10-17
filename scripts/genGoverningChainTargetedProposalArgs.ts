import { RoundTripProposalCreator, L1GovConfig, UpgradeConfig } from "../src-ts/proposalCreator";
import { JsonRpcProvider } from "@ethersproject/providers";
import { importDeployedContracts } from "../src-ts/utils";
import { getL1Network, getL2Network } from "@arbitrum/sdk";
import { BigNumber, utils } from "ethers";

const goerliDeployedContracts = importDeployedContracts("./files/goerli/deployedContracts.json");
const mainnetDeployedContracts = importDeployedContracts("./files/mainnet/deployedContracts.json");

const ensureContract = async (address: string, provider: JsonRpcProvider) => {
  if ((await provider.getCode(address)).length <= 2)
    throw new Error(`${address} contract not found`);
};

// Generate the ArbSys.sendTxToL1 arguments for a proposal whose action contract resides on a governance chain (i.e, Arb One or Arb Goerli)
export const generateArbSysArgs = async (
  l1Provider: JsonRpcProvider,
  l2Provider: JsonRpcProvider,
  l2UpgradeAddr: string,
  description: string,
  useSchedule = false,
  upgradeValue = BigNumber.from(0),
  actionIfaceStr = "function perform() external",
  upgradeArgs = [],
) => {
  const actionIface = new utils.Interface([actionIfaceStr]);
  const upgradeData = actionIface.encodeFunctionData("perform", upgradeArgs);

  const l1Network = await getL1Network(l1Provider);
  const l2Network = await getL2Network(l2Provider);

  if (!l1Network.partnerChainIDs.includes(l2Network.chainID))
    throw new Error("Unsupported chain pairing");

  const deployedContracts = (() => {
    switch (l1Network.chainID) {
      case 1:
        return mainnetDeployedContracts;
      case 5:
        return goerliDeployedContracts;
      default:
        throw new Error("Unsupported l1 chain");
    }
  })();
  const { l1Timelock, l2Executor } = deployedContracts;

  await ensureContract(l2UpgradeAddr, l2Provider);
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

  const proposalCreator = new RoundTripProposalCreator(L1GovConfig, [upgradeConfig]);
  return proposalCreator.createRoundTripCallDataForArbSysCall([l2UpgradeAddr], [upgradeValue],[upgradeData], description, useSchedule);
};
