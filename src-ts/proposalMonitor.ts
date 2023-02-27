import { Provider } from "@ethersproject/providers";
import { L2ArbitrumGovernor__factory } from "../typechain-types";
import { ProposalCreatedEventObject } from "../typechain-types/src/L2ArbitrumGovernor";
import { wait } from "./utils";
import {
  ProposalStagePipelineFactory,
  ProposalStageStatus,
  ProposalStageTracker,
} from "./proposalStage";
import { EventEmitter } from "events";

export enum GPMEventName {
  TRACKER_STARTED = "TRACKER_STARTED",
  TRACKER_ENDED = "TRACKER_ENDED",
  TRACKER_ERRORED = "TRACKER_ERRORED",
  /**
   * The stage being tracked has changed, or has changed status
   */
  TRACKER_STATUS = "TRACKED_STATUS",
}
export interface GPMEvent {
  governorAddress: string;
  proposalId: string;
}
export interface GPMErroredEvent extends GPMEvent {
  error: Error;
}
export interface GPMStatusEvent extends GPMEvent {
  status: ProposalStageStatus;
  stage: string;
  identifier: string;
}
export type GPMAllEvent = GPMEvent | GPMErroredEvent;

/**
 * Monitors a governor contract for created proposals. Starts a new proposal pipeline when
 * a proposal is created.
 */
export class GovernorProposalMonitor extends EventEmitter {
  constructor(
    public readonly governorAddress: string,
    public readonly governorProvider: Provider,
    public readonly pollingIntervalMs: number,
    public readonly blockLag: number,
    public readonly startBlockNumber: number,
    public readonly pipelineFactory: ProposalStagePipelineFactory
  ) {
    super();
  }

  public emit(eventName: GPMEventName.TRACKER_STARTED, args: GPMEvent): boolean;
  public emit(eventName: GPMEventName.TRACKER_ENDED, args: GPMEvent): boolean;
  public emit(eventName: GPMEventName.TRACKER_ERRORED, args: GPMErroredEvent): boolean;
  public emit(eventName: GPMEventName.TRACKER_STATUS, args: GPMStatusEvent): boolean;
  public override emit(eventName: GPMEventName, args: GPMAllEvent) {
    return super.emit(eventName, args);
  }

  private polling = false;

  public async monitorSingleProposal(log: ProposalCreatedEventObject) {
    const gen = this.pipelineFactory.createPipeline(
      this.governorAddress,
      log.proposalId.toHexString(),
      log.targets[0],
      (log as any)[3][0], // ethers is parsing an array with a single 0 big number as undefined, so we lookup by index
      log.calldatas[0],
      log.description
    );

    const propStageTracker = new ProposalStageTracker(gen, this.pollingIntervalMs);
    propStageTracker.on("status", (args) =>
      this.emit(GPMEventName.TRACKER_STATUS, {
        governorAddress: this.governorAddress,
        proposalId: log.proposalId.toHexString(),
        ...args,
      })
    );

    this.emit(GPMEventName.TRACKER_STARTED, {
      governorAddress: this.governorAddress,
      proposalId: log.proposalId.toHexString(),
    });

    propStageTracker
      .run()
      .then(() => {
        this.emit(GPMEventName.TRACKER_ENDED, {
          governorAddress: this.governorAddress,
          proposalId: log.proposalId.toHexString(),
        });
      })
      .catch((e) => {
        // an error in the runner shouldn't halt the whole monitor,
        // as doing so would halt other successful runners. Emit the info
        // to be handled elsewhere
        this.emit(GPMEventName.TRACKER_ERRORED, {
          governorAddress: this.governorAddress,
          proposalId: log.proposalId.toHexString(),
          error: e,
        });
      });
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
        (await this.governorProvider.getBlockNumber()) - this.blockLag,
        blockThen
      );

      const governor = L2ArbitrumGovernor__factory.connect(
        this.governorAddress,
        this.governorProvider
      );

      const proposalCreatedFilter =
        governor.filters[
          "ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)"
        ]();
      const logs = (
        await this.governorProvider.getLogs({
          fromBlock: blockThen,
          toBlock: blockNow - 1,
          ...proposalCreatedFilter,
        })
      ).map((l) => governor.interface.parseLog(l).args as unknown as ProposalCreatedEventObject);
      for (const log of logs) {
        await this.monitorSingleProposal(log);
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
