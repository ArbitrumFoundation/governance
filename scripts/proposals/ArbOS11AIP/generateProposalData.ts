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
  "0xe8e5dc1793d6fe39452ddcb90d12997fa39de1de",
  "0x6B125347f3B0790197d5247f32f91fd3e7140eD7",
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

  const propData = await propCreator.createRoundTripCallData(
    actionAddresses,
    values,
    datas,
    description
  );
  console.log(propData);

  const proposal: CoreGovPropposal = {
    actionChainID: [1, 1, 42161, 42170],
    actionAddress: actionAddresses,
    description,
    arbSysSendTxToL1Args: {
      l1Timelock: mainnetDeployedContracts.l1Timelock,
      calldata: propData,
    },
  };

  const path = `${__dirname}/data/ArbOS-11-AIP-data.json`;
  fs.writeFileSync(path, JSON.stringify(proposal, null, 2));
  console.log("Wrote proposal data to", path);
};

main().then(() => {
  console.log("done");
});
