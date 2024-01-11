import { RoundTripProposalCreator } from "./../../../src-ts/proposalCreator";
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

const description = fs.readFileSync("./scripts/proposals/ArbOS11AIP/description.txt").toString()

if(!process.env.ETH_URL) throw new Error("no eth rpc")
if(!process.env.ARB_URL) throw new Error("no arb1 rpc")
if(!process.env.NOVA_URL) throw new Error("no nova rpc")

const l1Provider = new JsonRpcProvider(process.env.ETH_URL);
const govChainProvider = new JsonRpcProvider(process.env.ARB_URL);
const novaProvider = new JsonRpcProvider(process.env.NOVA_URL);

const l1GovConfig = {
  timelockAddr: mainnetDeployedContracts.l1Timelock,
  provider: l1Provider,
};

if (!mainnetDeployedContracts.novaUpgradeExecutorProxy)
  throw new Error("novaUpgradeExecutorProxy not found");
const upgradeExecs = [
  {
    upgradeExecutorAddr: mainnetDeployedContracts.l1Executor,
    provider: l1Provider,
  },
  {
    upgradeExecutorAddr: mainnetDeployedContracts.l1Executor,
    provider: l1Provider,
  },
  {
    upgradeExecutorAddr: mainnetDeployedContracts.l2Executor,
    provider: govChainProvider,
  },
  {
    upgradeExecutorAddr: mainnetDeployedContracts.novaUpgradeExecutorProxy,
    provider: novaProvider,
  },
];

const actionAddresses = [
  "0x3b70f2da6f3b01f9a53dcbcb3e59ad3ad8bed924",
  "0x54c2c372943572ac2a8e84d502ebc13f14b62246",
  "0xF6c7Dc6eaE78aBF2f32df899654ca425Dfa99481",
  "0x5357f4d3e8f8250a77bcddd5e58886ad1358220c",
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
  console.log(res.l1TimelockScheduleCallData);

  const proposal: CoreGovPropposal = {
    actionChainID: [1, 1, 42161, 42170],
    actionAddress: actionAddresses,
    description,
    arbSysSendTxToL1Args: {
      l1Timelock: mainnetDeployedContracts.l1Timelock,
      calldata: res.l1TimelockScheduleCallData,
    },
  };

  const path = `${__dirname}/data/ArbOS-11-AIP-data.json`;
  fs.writeFileSync(path, JSON.stringify(proposal, null, 2));
  console.log("Wrote proposal data to", path);
};

main().then(() => {
  console.log("done");
});
