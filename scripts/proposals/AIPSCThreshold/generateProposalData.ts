import { RoundTripProposalCreator } from "../../../src-ts/proposalCreator";
import { JsonRpcProvider } from "@ethersproject/providers";
import { constants, utils } from "ethers";
import { CoreGovPropposal } from "../coreGovProposalInterface";
import dotenv from "dotenv";
import { importDeployedContracts } from "../../../src-ts/utils";
import fs from "fs";
const zero = constants.Zero;
dotenv.config();

const mainnetDeployedContracts = importDeployedContracts("./files/mainnet/deployedContracts.json");

dotenv.config();

const description = fs.readFileSync("./scripts/proposals/AIPSCThreshold/description.txt").toString()

if(!process.env.ETH_URL) throw new Error("no eth rpc")
if(!process.env.ARB_URL) throw new Error("no arb1 rpc")

const l1Provider = new JsonRpcProvider(process.env.ETH_URL);
const govChainProvider = new JsonRpcProvider(process.env.ARB_URL);

const l1GovConfig = {
  timelockAddr: mainnetDeployedContracts.l1Timelock,
  provider: l1Provider,
};

if (!mainnetDeployedContracts.novaUpgradeExecutorProxy)
  throw new Error("novaUpgradeExecutorProxy not found");
const upgradeExecs = [
  {
    upgradeExecutorAddr: mainnetDeployedContracts.l2Executor,
    provider: govChainProvider,
  },
];

const actionAddresses = [
  "0x25afB879bb5364cB3f7e0b607AD280C0F52B0D82",
];

const performEncoded = new utils.Interface(["function perform() external"]).encodeFunctionData(
  "perform",
  []
);

const values = actionAddresses.map(() => zero);
const datas = actionAddresses.map(() => performEncoded);

const main = async () => {
  const propCreator = new RoundTripProposalCreator(l1GovConfig, upgradeExecs);

  const res = await propCreator.createRoundTripCallDataForArbSysCall(
    actionAddresses,
    values,
    datas,
    description
  );

  const proposal: CoreGovPropposal = {
    actionChainID: [42161],
    actionAddress: actionAddresses,
    description,
    arbSysSendTxToL1Args: {
      l1Timelock: mainnetDeployedContracts.l1Timelock,
      calldata: res.l1TimelockScheduleCallData,
    },
  };

  const path = `${__dirname}/data/AIPSCThreshold-data.json`;
  fs.writeFileSync(path, JSON.stringify(proposal, null, 2));
  console.log("Wrote proposal data to", path);
};

main().then(() => {
  console.log("done");
});
