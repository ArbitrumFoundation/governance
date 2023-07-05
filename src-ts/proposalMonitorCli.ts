import { Wallet } from "ethers";
import { JsonRpcProvider } from "@ethersproject/providers";
import { ProposalStageStatus, RoundTripProposalPipelineFactory } from "./proposalStage";
import { GPMEventName, GPMStatusEvent, GovernorProposalMonitor } from "./proposalMonitor";
import dotenv from "dotenv";
dotenv.config();
import yargs from "yargs";

const ETH_KEY = process.env.ETH_KEY || "";
if (!ETH_KEY) throw new Error("env var ETH_KEY required");

const ARB_KEY = process.env.ARB_KEY || "";
if (!ARB_KEY) throw new Error("env var ARB_KEY required");

const options = yargs(process.argv.slice(2))
  .options({
    l1RpcUrl: { type: "string", demandOption: true },
    govChainRPCUrl: { type: "string", demandOption: true },
    novaRPCUrl: { type: "string", demandOption: true },
    governorAddress: { type: "string", demandOption: true },
    startBlock: { type: "number", demandOption: false, default: 72559827 },
    pollingIntervalMinutes: { type: "number", demandOption: false, default: 5 },
    blockLag: { type: "number", demandOption: false, default: 5 },
  })
  .parseSync() as {
  l1RpcUrl: string;
  govChainRPCUrl: string;
  novaRPCUrl: string;
  governorAddress: string;
  startBlock: number;
  pollingIntervalMinutes: number;
  blockLag: number;
};
const main = async () => {
  const l1Signer = new Wallet(ETH_KEY, new JsonRpcProvider(options.l1RpcUrl));
  const govChainSigner = new Wallet(ARB_KEY, new JsonRpcProvider(options.govChainRPCUrl));
  const novaSigner = new Wallet(ARB_KEY, new JsonRpcProvider(options.novaRPCUrl));
  const pipelineFactory = new RoundTripProposalPipelineFactory(govChainSigner, l1Signer, novaSigner);

  const proposalMonitor = new GovernorProposalMonitor(
    options.governorAddress,
    govChainSigner.provider!,
    options.pollingIntervalMinutes * 60 * 1000,
    options.blockLag,
    options.startBlock,
    pipelineFactory
  );

  proposalMonitor.on(GPMEventName.TRACKER_STARTED, (e: GPMStatusEvent) => {
    console.log(`Tracker started:  Gov:${e.governorAddress}, Prop:${e.proposalId}`);
  });

  proposalMonitor.on(GPMEventName.TRACKER_ENDED, (e: GPMStatusEvent) => {
    console.log(`Tracker ended:  Gov:${e.governorAddress}, Prop:${e.proposalId}`);
  });

  proposalMonitor.on(GPMEventName.TRACKER_ERRORED, (e: GPMStatusEvent) => {
    console.log(`Tracker errored:  Gov:${e.governorAddress}, Prop:${e.proposalId} Error:`, e);
  });
  proposalMonitor.on(GPMEventName.TRACKER_STATUS, (e: GPMStatusEvent) => {
    console.log(
      `Gov:${e.governorAddress}, Prop:${e.proposalId}, Stage:${e.stage}, Status:${
        ProposalStageStatus[e.status]
      }`
    );
  });
  await proposalMonitor.start();
};

main().then(() => console.log("Done."));