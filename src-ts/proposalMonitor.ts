import { BlockTag, Provider, TransactionReceipt } from "@ethersproject/providers";
import { L2ArbitrumGovernor__factory } from "../typechain-types";
import { ProposalCreatedEventObject } from "../typechain-types/src/L2ArbitrumGovernor";
import { getLogsWithCache, wait } from "./utils";
import {
  StageFactory,
  StageTracker,
  TrackerEventName,
  TrackerEvent,
  AllTrackerEvents,
} from "./proposalPipeline";
import { EventEmitter } from "events";
import { Interface } from "@ethersproject/abi";
import { BigNumber } from "ethers";
import axios from "axios";

export type GPMEvent = TrackerEvent & { originAddress: string };

export abstract class ProposalMonitor extends EventEmitter {
  constructor(
    public readonly originAddress: string,
    public readonly originProvider: Provider,
    public readonly pollingIntervalMs: number,
    public readonly startBlockNumber: number,
    public readonly stageFactory: StageFactory,
    public readonly writeMode: boolean,
    public readonly healthCheckUrl?: string
  ) {
    super();
  }

  public override emit(eventName: TrackerEventName, args: GPMEvent) {
    return super.emit(eventName, args);
  }

  public override on(eventName: TrackerEventName, listener: (args: GPMEvent) => void): this {
    return super.on(eventName, listener);
  }

  private polling = false;

  public async waitAndPing(){    
    await wait(this.pollingIntervalMs);
    if(this.healthCheckUrl){
      axios.get(this.healthCheckUrl).catch((err)=>{
        console.log("healthcheck ping error", err);
      })
    }
  }

  public async monitorSingleProposal(receipt: TransactionReceipt) {
    const nextStages = await this.stageFactory.extractStages(receipt);

    for (const nStage of nextStages) {
      const tracker = new StageTracker(
        this.stageFactory,
        nStage,
        this.pollingIntervalMs,
        this.writeMode
      );

      for (const ev of AllTrackerEvents) {
        tracker.on(ev, (args) => {
          this.emit(ev, {
            ...args,
            originAddress: this.originAddress,
          });
        });
      }

      tracker.run();
    }
  }

  public abstract getOriginTxHashes(
    fromBlock: BlockTag,
    originId?: string
  ): Promise<string[]>;

  public async start() {
    if (this.polling === true) {
      throw new Error("Proposal monitor already started");
    }
    this.polling = true;

    await this.waitAndPing();

    const seenTransactions = new Set<string>();

    while (this.polling) {
      try {
        const txHashes = await this.getOriginTxHashes(this.startBlockNumber);

        for (const hash of txHashes) {
          if (seenTransactions.has(hash)) {
            continue;
          }
          await this.monitorSingleProposal(await this.originProvider.getTransactionReceipt(hash));
          seenTransactions.add(hash);
        }
      } catch (err) {
        console.log("Proposal monitor Error:", err);
      }

      await this.waitAndPing();
    }
  }

  public async stop() {
    if (this.polling === false) {
      throw new Error("Proposal monitor not already started");
    }
    this.polling = false;
  }
}

/**
 * Monitors a governor contract for created proposals. Starts a new proposal pipeline when
 * a proposal is created.
 */
export class GovernorProposalMonitor extends ProposalMonitor {
  public override async getOriginTxHashes(
    fromBlock: BlockTag,
    proposalId?: string
  ) {
    const governor = L2ArbitrumGovernor__factory.connect(this.originAddress, this.originProvider);
    const logs = await getLogsWithCache(this.originProvider, {
      fromBlock,
      toBlock: 'finalized',
      ...governor.filters.ProposalCreated(),
    });

    const filteredTxHashes = logs
      .filter(
        (l) =>
          !proposalId ||
          (
            governor.interface.parseLog(l).args as unknown as ProposalCreatedEventObject
          ).proposalId.toHexString() === proposalId
      )
      .map((l) => l.transactionHash);

    return Array.from(new Set(filteredTxHashes))
  }
}

export class GnosisSafeProposalMonitor extends ProposalMonitor {
  public override async getOriginTxHashes(fromBlock: BlockTag, txHash?: string) {
    const gnosisSafeInterface = new Interface([
      "event ExecutionSuccess(bytes32 indexed txHash, uint256 payment)",
    ]);
    const executionSuccessEvent = gnosisSafeInterface.encodeFilterTopics("ExecutionSuccess", []);
    const logs = await getLogsWithCache(this.originProvider, {
      fromBlock,
      toBlock: 'finalized',
      topics: executionSuccessEvent,
      address: this.originAddress,
    });

    const filteredTxHashes = logs
      .filter(
        (l) =>
          !txHash ||
          (
            gnosisSafeInterface.parseLog(l).args as unknown as {
              txHash: string;
              payment: BigNumber;
            }
          ).txHash === txHash
      )
      .map((l) => l.transactionHash);

    return Array.from(new Set(filteredTxHashes))
  }
}
