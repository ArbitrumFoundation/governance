import { BlockTag, Provider, TransactionReceipt } from "@ethersproject/providers";
import { L2ArbitrumGovernor__factory } from "../typechain-types";
import { ProposalCreatedEventObject } from "../typechain-types/src/L2ArbitrumGovernor";
import { wait } from "./utils";
import {
  StageFactory,
  StageTracker,
  TrackerEventName,
  TrackerEvent,
  TrackerErrorEvent,
} from "./proposalPipeline";
import { EventEmitter } from "events";

export type GPMEvent = TrackerEvent & { originAddress: string };
export type GPMErrorEvent = TrackerErrorEvent & { originAddress: string };

/**
 * Monitors a governor contract for created proposals. Starts a new proposal pipeline when
 * a proposal is created.
 */
export class ProposalMonitor extends EventEmitter {
  constructor(
    public readonly originAddress: string,
    public readonly originProvider: Provider,
    public readonly pollingIntervalMs: number,
    public readonly blockLag: number,
    public readonly startBlockNumber: number,
    public readonly stageFactory: StageFactory,
    public readonly writeMode: boolean
  ) {
    super();
  }

  public emit(eventName: TrackerEventName.TRACKER_STARTED, args: GPMEvent): boolean;
  public emit(eventName: TrackerEventName.TRACKER_ENDED, args: GPMEvent): boolean;
  public emit(eventName: TrackerEventName.TRACKER_ERRORED, args: GPMErrorEvent): boolean;
  public emit(eventName: TrackerEventName.TRACKER_STATUS, args: GPMEvent): boolean;
  public override emit(eventName: TrackerEventName, args: GPMEvent | GPMErrorEvent) {
    return super.emit(eventName, args);
  }

  public on(eventName: TrackerEventName.TRACKER_STARTED, listener: (args: GPMEvent) => void): this;
  public on(eventName: TrackerEventName.TRACKER_ENDED, listener: (args: GPMEvent) => void): this;
  public on(
    eventName: TrackerEventName.TRACKER_ERRORED,
    listener: (args: GPMErrorEvent) => void
  ): this;
  public on(eventName: TrackerEventName.TRACKER_STATUS, listener: (args: GPMEvent) => void): this;
  public override on(
    eventName: TrackerEventName,
    listener: ((args: GPMEvent) => void) | ((args: GPMErrorEvent) => void)
  ): this {
    return super.on(eventName, listener);
  }

  private polling = false;

  public async monitorSingleProposal(receipt: TransactionReceipt) {
    const nextStages = await this.stageFactory.nextStages(receipt);

    for (const nStage of nextStages) {
      const tracker = new StageTracker(
        this.stageFactory,
        nStage,
        this.pollingIntervalMs,
        this.writeMode
      );

      tracker.on(TrackerEventName.TRACKER_STATUS, (args) =>
        this.emit(TrackerEventName.TRACKER_STATUS, {
          originAddress: this.originAddress,
          ...args,
        })
      );
      tracker.on(TrackerEventName.TRACKER_STARTED, (args) =>
        this.emit(TrackerEventName.TRACKER_STARTED, {
          originAddress: this.originAddress,
          ...args,
        })
      );
      tracker.on(TrackerEventName.TRACKER_ERRORED, (args) =>
        this.emit(TrackerEventName.TRACKER_ERRORED, {
          originAddress: this.originAddress,
          ...args,
        })
      );
      tracker.on(TrackerEventName.TRACKER_ENDED, (args) =>
        this.emit(TrackerEventName.TRACKER_ENDED, {
          originAddress: this.originAddress,
          ...args,
        })
      );
      tracker.run();
    }
  }

  public async getProposalCreatedTransactions(
    fromBlock: BlockTag,
    toBlock: BlockTag,
    proposalId?: string
  ) {
    const governor = L2ArbitrumGovernor__factory.connect(this.originAddress, this.originProvider);

    const proposalCreatedFilter =
      governor.filters[
        "ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)"
      ]();

    const receipts = await Promise.all(
      Array.from(
        new Set(
          (
            await this.originProvider.getLogs({
              fromBlock,
              toBlock,
              ...proposalCreatedFilter,
            })
          )
            .filter((l) => {
              return (
                !proposalId ||
                (
                  governor.interface.parseLog(l).args as unknown as ProposalCreatedEventObject
                ).proposalId.toHexString() === proposalId
              );
            })
            .map((l) => l.transactionHash)
        )
      ).map((t) => this.originProvider.getTransactionReceipt(t))
    );

    return receipts;
  }

  public async start() {
    if (this.polling === true) {
      throw new Error("Proposal monitor already started");
    }
    this.polling = true;

    let blockThen = this.startBlockNumber;
    await wait(this.pollingIntervalMs);

    while (this.polling) {
      const blockNow = Math.max(
        (await this.originProvider.getBlockNumber()) - this.blockLag,
        blockThen
      );

      const receipts = await this.getProposalCreatedTransactions(blockThen, blockNow);

      for (const r of receipts) {
        await this.monitorSingleProposal(r);
      }

      await wait(this.pollingIntervalMs);
      blockThen = blockNow;
    }
  }

  public async stop() {
    if (this.polling === false) {
      throw new Error("Proposal monitor not already started");
    }
    this.polling = false;
  }
}
