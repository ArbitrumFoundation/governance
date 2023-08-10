import { RoundTripProposalCreator } from "../src-ts/proposalCreator";
import yargs from "yargs";
import { JsonRpcProvider } from "@ethersproject/providers";
import { BigNumber } from "ethers";
import { addCustomNetwork, L1Network, L2Network } from "@arbitrum/sdk";
import * as path from "path";
import * as fs from "fs";
const options = yargs(process.argv.slice(2))
  .options({
    l1RpcUrl: { type: "string", demandOption: true },
    l1TimelockAddress: { type: "string", demandOption: true },
    upgradeNetworkRpcUrl: { type: "string", demandOption: true },
    upgradeExecutorAddress: { type: "string", demandOption: true },
    upgradeAddress: { type: "string", demandOption: true },
    upgradeValue: { type: "string", demandOption: true },
    upgradeData: { type: "string", demandOption: true },
    proposalDescription: { type: "string", demandOption: true },
  })
  .parseSync() as {
  l1RpcUrl: string;
  l1TimelockAddress: string;
  upgradeNetworkRpcUrl: string;
  upgradeExecutorAddress: string;
  upgradeAddress: string;
  upgradeValue: string;
  upgradeData: string;
  proposalDescription: string;
};

const localNetworkFile = path.join(__dirname, "..", "localNetwork.json");
if (fs.existsSync(localNetworkFile)) {
  const { l1Network, l2Network } = JSON.parse(
    fs.readFileSync(localNetworkFile).toString()
  ) as {
    l1Network: L1Network;
    l2Network: L2Network;
  };
  addCustomNetwork({
    customL1Network: l1Network,
    customL2Network: l2Network,
  });
}

const propCreator = new RoundTripProposalCreator(
  {
    provider: new JsonRpcProvider(options.l1RpcUrl),
    timelockAddr: options.l1TimelockAddress,
  },
  [{
    provider: new JsonRpcProvider(options.upgradeNetworkRpcUrl),
    upgradeExecutorAddr: options.upgradeExecutorAddress,
  }]
);

propCreator
  .create(
    [options.upgradeAddress],
    [BigNumber.from(options.upgradeValue)],
    [options.upgradeData],
    options.proposalDescription
  )
  .then((p) => console.log(p.callData))
  .catch((e) => console.error(e));
