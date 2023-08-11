import { BigNumber, Signer, Wallet } from "ethers";
import { JsonRpcProvider, Provider } from "@ethersproject/providers";
import {
  GovernorQueueStage,
  ProposalStage,
  ProposalStageStatus,
  getProvider,
} from "./proposalStage";
import { StageFactory, TrackerEventName } from "./proposalPipeline";
import * as dotenv from "dotenv";
import * as fs from "fs";
dotenv.config();
import yargs from "yargs";
import { wait } from "./utils";
import * as path from "path";
import { GPMErrorEvent, GPMEvent, ProposalMonitor } from "./proposalMonitor";

const ETH_KEY = process.env.ETH_KEY || "";
const ARB_KEY = process.env.ARB_KEY || "";

const options = yargs(process.argv.slice(2))
  .options({
    l1RpcUrl: { type: "string", demandOption: true },
    govChainRpcUrl: { type: "string", demandOption: true },
    novaRpcUrl: { type: "string", demandOption: true },
    coreGovernorAddress: { type: "string", demandOption: true },
    treasuryGovernorAddress: { type: "string", demandOption: true },
    startBlock: { type: "number", demandOption: false, default: 72559827 },
    pollingIntervalSeconds: { type: "number", demandOption: false, default: 300 },
    blockLag: { type: "number", demandOption: false, default: 5 },
    writeMode: { type: "boolean", demandOption: false, default: false },
    jsonOutputLocation: { type: "string", demandOption: false },
    proposalId: { type: "string", demandOption: false },
  })
  .parseSync() as {
  l1RpcUrl: string;
  govChainRpcUrl: string;
  novaRpcUrl: string;
  coreGovernorAddress: string;
  treasuryGovernorAddress: string;
  startBlock: number;
  pollingIntervalSeconds: number;
  blockLag: number;
  writeMode: boolean;
  proposalId?: string;
  jsonOutputLocation?: string;
};

const attachConsole = (proposalMonitor: ProposalMonitor, monitorName: string) => {
  proposalMonitor.on(TrackerEventName.TRACKER_STARTED, (e: GPMEvent) => {
    console.log(`${monitorName} tracker started:  Gov:${e.originAddress}, Stage:${e.identifier}`);
  });

  proposalMonitor.on(TrackerEventName.TRACKER_ENDED, (e: GPMEvent) => {
    console.log(`${monitorName} tracker ended:  Gov:${e.originAddress}, Prop:${e.identifier}`);
  });

  proposalMonitor.on(TrackerEventName.TRACKER_ERRORED, (e: GPMErrorEvent) => {
    console.log(
      `${monitorName} tracker errored:  Gov:${e.originAddress}, Prop:${e.identifier} Stage:${
        e.stage
      } Status:${ProposalStageStatus[e.status]} Error: ${e.error}`
    );
  });
  proposalMonitor.on(TrackerEventName.TRACKER_STATUS, (e: GPMEvent) => {
    console.log(
      `${monitorName} status update:  Gov:${e.originAddress}, Prop:${e.identifier}  Stage:${
        e.stage
      } Status:${ProposalStageStatus[e.status]}`
    );
  });
};

const startMonitor = async (
  monitorName: string,
  governorAddress: string,
  govChainSignerOrProvider: Signer | Provider,
  l1SignerOrProvider: Signer | Provider,
  novaSignerOrProvider: Signer | Provider,
  jsonLogger?: JsonLogger,
  proposalId?: string
) => {
  const proposalMonitor = new ProposalMonitor(
    governorAddress,
    getProvider(govChainSignerOrProvider)!,
    options.pollingIntervalSeconds * 1000,
    options.blockLag,
    options.startBlock,
    new StageFactory(
      options.startBlock,
      govChainSignerOrProvider,
      l1SignerOrProvider,
      novaSignerOrProvider
    ),
    options.writeMode
  );
  attachConsole(proposalMonitor, monitorName);

  if (jsonLogger) {
    jsonLogger.subscribeToMonitor(proposalMonitor);
  }
  if (proposalId) {
    const receipts = await proposalMonitor.getProposalCreatedTransactions(
      options.startBlock,
      "latest",
      proposalId
    );
    if (receipts.length !== 1) {
      throw new Error(`Proposal not found: ${proposalId}`);
    }
    await proposalMonitor.monitorSingleProposal(receipts[0]);
  } else {
    await proposalMonitor.start();
  }
};

interface PipelineStage {
  name: string;
  identifier: string;
  status: string;
  explorerLink?: string;
  proposalLink?: string;
  children: PipelineStage[];
}

interface GovernorStatus {
  [governorAddress: string]: PipelineStage[];
}

class JsonLogger {
  constructor(public readonly fileLocation: string, public flushingIntervalMs: number) {}

  private data: GovernorStatus = {};
  private writing = false;

  private writeToFile() {
    const data = JSON.stringify(this.data, null, 2);
    fs.writeFileSync(this.fileLocation, data);
  }

  public stop() {
    this.writing = false;
  }

  public async start() {
    this.writing = true;
    while (this.writing) {
      this.writeToFile();
      await wait(this.flushingIntervalMs);
    }
  }

  public subscribeToMonitor(proposalMonitor: ProposalMonitor) {
    const emittedStages: Map<string, PipelineStage> = new Map();
    const originKey = `${proposalMonitor.originAddress}::`;

    proposalMonitor.on(TrackerEventName.TRACKER_ERRORED, (e: GPMErrorEvent) => {
      console.log(e);
      console.log("Error!");
      // CHRIS: TODO: clean up in here
    });

    proposalMonitor.on(TrackerEventName.TRACKER_STATUS, (e: GPMEvent) => {
      if (!this.data[proposalMonitor.originAddress]) {
        this.data[proposalMonitor.originAddress] = [];
      }

      const key = `${e.originAddress}:${e.stage}:${e.identifier}`;
      const prevKey = `${e.originAddress}:${e.prevStage?.stage || ""}:${
        e.prevStage?.identifier || ""
      }`;

      let proposalLink: string | undefined;
      if (prevKey === originKey && e.stage === "GovernorQueueStage") {
        proposalLink =
          "https://www.tally.xyz/gov/arbitrum/proposal/" + BigNumber.from(e.identifier).toString();
      }

      // create a stage from this event
      const pipelineStage: PipelineStage = {
        name: e.stage,
        identifier: e.identifier,
        status: ProposalStageStatus[e.status],
        explorerLink: e.publicExecutionUrl,
        proposalLink,
        children: [],
      };

      if (prevKey === originKey && !emittedStages.has(key)) {
        this.data[proposalMonitor.originAddress].push(pipelineStage);
      } else {
        const prevStage = emittedStages.get(prevKey);
        if (!prevStage) {
          throw new Error(`Could not find prev stage ${prevKey} for ${key}`);
        }
        prevStage.children.push(pipelineStage);
      }

      // set the stage
      if (!emittedStages.has(key)) {
        emittedStages.set(key, pipelineStage);
      } else {
        emittedStages.get(key)!.status = pipelineStage.status;
      }
    });
  }
}

const main = async () => {
  if (options.writeMode && !ARB_KEY) throw new Error("env var ARB_KEY required");
  if (options.writeMode && !ETH_KEY) throw new Error("env var ETH_KEY required");

  const l1Provider = new JsonRpcProvider(options.l1RpcUrl);
  const l1SignerOrProvider = options.writeMode ? new Wallet(ETH_KEY, l1Provider) : l1Provider;
  const govChainProvider = new JsonRpcProvider(options.govChainRpcUrl);
  const govChainSignerOrProvider = options.writeMode
    ? new Wallet(ARB_KEY, govChainProvider)
    : govChainProvider;
  const novaProvider = new JsonRpcProvider(options.novaRpcUrl);
  const novaSignerOrProvider = options.writeMode ? new Wallet(ARB_KEY, novaProvider) : novaProvider;

  let jsonLogger;
  if (options.jsonOutputLocation) {
    jsonLogger = new JsonLogger(options.jsonOutputLocation, 1000);
    jsonLogger.start();
  }

  // round trips originate from the core governor
  const roundTrip = startMonitor(
    "RoundTrip",
    options.coreGovernorAddress,
    govChainSignerOrProvider,
    l1SignerOrProvider,
    novaSignerOrProvider,
    jsonLogger,
    options.proposalId
  );

  // treasury proposals only have 1 timelock, so they can use the arb one only pipeline factory
  const treasury = startMonitor(
    "Treasury",
    options.treasuryGovernorAddress,
    govChainSignerOrProvider,
    l1SignerOrProvider,
    novaSignerOrProvider,
    jsonLogger,
    options.proposalId
  );

  await Promise.all([
    roundTrip,
    treasury
  ]);
};

main().then(() => console.log("Done."));
