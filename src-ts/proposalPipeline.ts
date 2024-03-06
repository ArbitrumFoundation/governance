import {
  GovernorQueueStage,
  L1OutboxStage,
  L1TimelockExecutionBatchStage,
  L1TimelockExecutionSingleStage,
  L2TimelockExecutionBatchStage,
  ProposalStage,
  ProposalStageError,
  ProposalStageStatus,
  RetryableExecutionStage,
  UnreachableCaseError,
  getProvider,
  BaseGovernorExecuteStage,
  L2TimelockExecutionSingleStage,
} from "./proposalStage";
import { Signer, BigNumber } from "ethers";
import { Provider, TransactionReceipt } from "@ethersproject/abstract-provider";
import { EventEmitter } from "events";
import { wait } from "./utils";

export class StageFactory {
  constructor(
    public readonly arbOneSignerOrProvider: Signer | Provider,
    public readonly l1SignerOrProvider: Signer | Provider,
    public readonly novaSignerOrProvider: Signer | Provider
  ) {}

  public async extractStages(receipt: TransactionReceipt): Promise<ProposalStage[]> {
    return [
      ...(await BaseGovernorExecuteStage.extractStages(receipt, this.arbOneSignerOrProvider)),
      ...(await L2TimelockExecutionBatchStage.extractStages(receipt, this.arbOneSignerOrProvider)),
      ...(await L2TimelockExecutionSingleStage.extractStages(receipt, this.arbOneSignerOrProvider)),
      ...(await L1TimelockExecutionSingleStage.extractStages(receipt, this.l1SignerOrProvider)),
      ...(await L1TimelockExecutionBatchStage.extractStages(receipt, this.l1SignerOrProvider)),
      ...(await RetryableExecutionStage.extractStages(receipt, this.arbOneSignerOrProvider)),
      ...(await RetryableExecutionStage.extractStages(receipt, this.novaSignerOrProvider)),
      ...(await L1OutboxStage.extractStages(
        receipt,
        this.l1SignerOrProvider,
        getProvider(this.arbOneSignerOrProvider)!
      )),
    ];
  }
}

export enum TrackerEventName {
  TRACKER_STARTED = "TRACKER_STARTED",
  TRACKER_ENDED = "TRACKER_ENDED",
  TRACKER_ERRORED = "TRACKER_ERRORED",
  /**
   * The stage being tracked has changed, or has changed status
   */
  TRACKER_STATUS = "TRACKED_STATUS",
}

export const AllTrackerEvents = Object.values(TrackerEventName);

export interface TrackerEvent {
  identifier: string;
  status: ProposalStageStatus;
  stage: string;
  prevStage?: Omit<TrackerEvent, "status">;
  publicExecutionUrl?: string;
  error?: Error;
  proposalDescription?: string;
  quorum?: BigNumber
}

export class StageTracker extends EventEmitter {
  constructor(
    public readonly stageFactory: StageFactory,
    public readonly stage: ProposalStage,
    public readonly pollingIntervalMs: number,
    public readonly writeMode: boolean
  ) {
    super();
  }

  public override emit(eventName: TrackerEventName, args: TrackerEvent) {
    return super.emit(eventName, args);
  }

  public override on(eventName: TrackerEventName, listener: (args: TrackerEvent) => void): this {
    return super.on(eventName, listener);
  }

  public async run() {
    let polling = true;
    let consecutiveErrors = 0;
    let currentStatus: ProposalStageStatus | undefined = undefined;
    this.emit(TrackerEventName.TRACKER_STARTED, {
      identifier: this.stage.identifier,
      stage: this.stage.name,
      status: await this.stage.status(),
    });

    while (polling) {
      try {
        const status = await this.stage.status();
        if (currentStatus !== status) {
          // emit an event if the status changes
          this.emit(TrackerEventName.TRACKER_STATUS, {
            status,
            stage: this.stage.name,
            identifier: this.stage.identifier,
            publicExecutionUrl:
              status === ProposalStageStatus.EXECUTED
                ? await this.stage.getExecutionUrl()
                : undefined,
            proposalDescription:
              this.stage instanceof GovernorQueueStage ? this.stage.description : undefined,
              quorum: this.stage instanceof BaseGovernorExecuteStage && status != ProposalStageStatus.PENDING  ? await this.stage.quorum() : undefined
          });
          currentStatus = status;
        }
        switch (status) {
          case ProposalStageStatus.TERMINATED:
            // end of the road
            return;
          case ProposalStageStatus.EXECUTED:
            // find the next stage and start it
            const execReceipt = await this.stage.getExecuteReceipt();
            const nextStages = await this.stageFactory.extractStages(execReceipt);

            for (const nStage of nextStages) {
              const tracker = new StageTracker(
                this.stageFactory,
                nStage,
                this.pollingIntervalMs,
                this.writeMode
              );

              // propagate events to the listener of this tracker - add some info about the previous stage
              for (const ev of AllTrackerEvents) {
                tracker.on(ev, (args) => {
                  this.emit(ev, {
                    ...args,
                    prevStage: args.prevStage || {
                      stage: this.stage.name,
                      identifier: this.stage.identifier,
                    },
                  });
                });
              }

              // run but dont await
              tracker.run();
            }

            // continue to the next stage - break the while loop
            polling = false;

            break;
          case ProposalStageStatus.PENDING:
          case ProposalStageStatus.ACTIVE:
            // keep checking status
            await wait(this.pollingIntervalMs);
            break;
          case ProposalStageStatus.READY:
            if (this.writeMode) {
              // ready, so execute
              await this.stage.execute();

              // sanity check
              const doneStatus = await this.stage.status();
              if (doneStatus !== ProposalStageStatus.EXECUTED) {
                throw new ProposalStageError(
                  "Stage executed but did not result in status 'EXECUTED'.",
                  this.stage.identifier,
                  this.stage.name
                );
              }
            } else {
              await wait(this.pollingIntervalMs);
            }
            break;
          default:
            throw new UnreachableCaseError(status);
        }

        consecutiveErrors = 0;
      } catch (err) {
        if (err instanceof ProposalStageError) throw err;
        if (err instanceof UnreachableCaseError) throw err;

        consecutiveErrors++;
        const error = err as Error;
        if (consecutiveErrors > 5) {
          // emit an error here
          this.emit(TrackerEventName.TRACKER_ERRORED, {
            status: currentStatus!,
            stage: this.stage.name,
            identifier: this.stage.identifier,
            error: error,
          });

          throw new ProposalStageError(
            "Consecutive error",
            this.stage.identifier,
            this.stage.name,
            error
          );
        }

        await wait(this.pollingIntervalMs);
      }
    }

    this.emit(TrackerEventName.TRACKER_ENDED, {
      identifier: this.stage.identifier,
      stage: this.stage.name,
      status: currentStatus!,
    });
  }
}
