import {
  L1ToL2Message,
  L1TransactionReceipt,
  L2TransactionReceipt,
  getL2Network,
} from "@arbitrum/sdk";
import {
  GovernorQueueStage,
  L1OutboxStage,
  L1TimelockExecutionStage,
  L2TimelockExecutionBatchStage,
  ProposalStage,
  ProposalStageError,
  ProposalStageStatus,
  RetryableExecutionStage,
  UnreachableCaseError,
  getProvider,
} from "./proposalStage";
import { ArbitrumTimelock__factory, L2ArbitrumGovernor__factory } from "../typechain-types";
import { BigNumber, Signer, constants, ethers } from "ethers";
import { Provider, TransactionReceipt } from "@ethersproject/abstract-provider";
import { EventEmitter } from "events";
import { wait } from "./utils";
import {
  ProposalCreatedEventObject,
  ProposalQueuedEventObject,
} from "../typechain-types/src/L2ArbitrumGovernor";
import { EventArgs } from "@arbitrum/sdk/dist/lib/dataEntities/event";
import { L2ToL1TxEvent as NitroL2ToL1TransactionEvent } from "@arbitrum/sdk/dist/lib/abi/ArbSys";
import { Bridge__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Bridge__factory";
import { BridgeCallTriggeredEventObject } from "../typechain-types/@arbitrum/nitro-contracts/src/bridge/IBridge";
import { InboxMessageKind } from "@arbitrum/sdk/dist/lib/dataEntities/message";
import { SubmitRetryableMessageDataParser } from "@arbitrum/sdk/dist/lib/message/messageDataParser";
import { id } from "ethers/lib/utils";

export class StageFactory {
  constructor(
    public readonly startBlock: number,
    public readonly arbOneSignerOrProvider: Signer | Provider,
    public readonly l1SignerOrProvider: Signer | Provider,
    public readonly novaSignerOrProvider: Signer | Provider
  ) {}

  public async getProposalCreatedData(
    governor: string,
    proposalId: string
  ): Promise<ProposalCreatedEventObject | undefined> {
    const govInterface = L2ArbitrumGovernor__factory.createInterface();
    const filterTopics = govInterface.encodeFilterTopics("ProposalCreated", []);
    const logs = await getProvider(this.arbOneSignerOrProvider)!.getLogs({
      fromBlock: this.startBlock,
      toBlock: "latest",
      address: governor,
      topics: filterTopics,
    });

    const proposalEvents = logs
      .map((log) => {
        const parsedLog = govInterface.parseLog(log);
        return parsedLog.args as unknown as ProposalCreatedEventObject;
      })
      .filter((event) => event.proposalId.toHexString() === proposalId);

    if (proposalEvents.length > 1) {
      throw new Error(`More than one proposal created event found for proposal ${proposalId}`);
    }

    return proposalEvents.length === 1 ? proposalEvents[0] : undefined;
  }

  public findTimelockAddress(operationId: string, logs: ethers.providers.Log[]) {
    const timelockInterface = ArbitrumTimelock__factory.createInterface();
    for (const log of logs) {
      if (
        log.topics.find((t) => t === timelockInterface.getEventTopic("CallScheduled")) &&
        log.topics.find((t) => t === operationId)
      ) {
        return log.address;
      }
    }
  }

  public async nextStages(receipt: TransactionReceipt): Promise<ProposalStage[]> {
    try {
      const govInterface = L2ArbitrumGovernor__factory.createInterface();
      const timelockInterface = ArbitrumTimelock__factory.createInterface();
      const bridgeInterface = Bridge__factory.createInterface();

      const proposalStages: ProposalStage[] = [];
      for (const log of receipt.logs) {
        if (log.topics.find((t) => t === govInterface.getEventTopic("ProposalCreated"))) {
          const propCreatedEvent = govInterface.parseLog(log)
            .args as unknown as ProposalCreatedEventObject;

          proposalStages.push(
            new GovernorQueueStage(
              propCreatedEvent.proposalId.toHexString(),
              propCreatedEvent.targets,
              (propCreatedEvent as any)[3], // ethers is parsing an array with a single 0 big number as undefined, so we lookup by index
              propCreatedEvent.calldatas,
              propCreatedEvent.description,
              log.address,
              this.arbOneSignerOrProvider
            )
          );
        } else if (log.topics.find((t) => t === govInterface.getEventTopic("ProposalQueued"))) {
          const propCreatedObj = govInterface.parseLog(log)
            .args as unknown as ProposalQueuedEventObject;
          const propCreatedEvent = await this.getProposalCreatedData(
            log.address,
            propCreatedObj.proposalId.toHexString()
          );
          if (!propCreatedEvent) {
            throw new Error(
              `Could not find proposal created event: ${propCreatedObj.proposalId.toHexString()}`
            );
          }
          // calculate the operation id, and look for it in this receipt
          const operationId = L2TimelockExecutionBatchStage.hashOperationBatch(
            propCreatedEvent.targets,
            (propCreatedEvent as any)[3],
            propCreatedEvent.calldatas,
            constants.HashZero,
            id(propCreatedEvent.description)
          );
          const timelockAddress = this.findTimelockAddress(operationId, receipt.logs);
          if (!timelockAddress) {
            throw new Error(`Could not find timelock address for operation id ${operationId}`);
          }
          // we know the operation id
          const executeBatch = new L2TimelockExecutionBatchStage(
            propCreatedEvent.targets,
            (propCreatedEvent as any)[3],
            propCreatedEvent.calldatas,
            constants.HashZero,
            id(propCreatedEvent.description),
            timelockAddress,
            this.arbOneSignerOrProvider
          );

          proposalStages.push(executeBatch);
        } else if (
          log.topics.find((t) => t === bridgeInterface.getEventTopic("BridgeCallTriggered"))
        ) {
          const bridgeCallTriggered = bridgeInterface.parseLog(log)
            .args as unknown as BridgeCallTriggeredEventObject;
          const data = bridgeCallTriggered.data;
          const funcSig = data.slice(0, 10);

          const schedFunc =
            timelockInterface.functions["schedule(address,uint256,bytes,bytes32,bytes32,uint256)"];
          const schedBatchFunc =
            timelockInterface.functions[
              "scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)"
            ];
          if (funcSig === timelockInterface.getSighash(schedFunc)) {
            const scheduleBatchData = L2TimelockExecutionBatchStage.decodeSchedule(data);
            const operationId = L2TimelockExecutionBatchStage.hashOperation(
              scheduleBatchData.target,
              scheduleBatchData.value,
              scheduleBatchData.callData,
              scheduleBatchData.predecessor,
              scheduleBatchData.salt
            );
            const timelockAddress = this.findTimelockAddress(operationId, receipt.logs);
            if (!timelockAddress) {
              throw new Error(`Could not find timelock address for operation id ${operationId}`);
            }

            proposalStages.push(
              new L1TimelockExecutionStage(
                timelockAddress,
                scheduleBatchData.target,
                scheduleBatchData.value,
                scheduleBatchData.callData,
                scheduleBatchData.predecessor,
                scheduleBatchData.salt,
                this.l1SignerOrProvider
              )
            );
          } else if (funcSig === timelockInterface.getSighash(schedBatchFunc)) {
            throw new Error("Schedule batch not implemented");
          }
        }
      }

      const l1Receipt = new L1TransactionReceipt(receipt);
      const l1ToL2Events = l1Receipt.getMessageEvents();
      for (const e of l1ToL2Events.filter(
        (e) => e.bridgeMessageEvent.kind === InboxMessageKind.L1MessageType_submitRetryableTx
      )) {
        let providerOrSigner: Signer | Provider;
        let chainId: number;

        const arbOneNetwork = await getL2Network(this.arbOneSignerOrProvider);
        const novaNetwork = await getL2Network(this.novaSignerOrProvider);
        if (
          e.bridgeMessageEvent.inbox.toLowerCase() === arbOneNetwork.ethBridge.inbox.toLowerCase()
        ) {
          providerOrSigner = this.arbOneSignerOrProvider;
          chainId = arbOneNetwork.chainID;
        } else if (
          e.bridgeMessageEvent.inbox.toLowerCase() === novaNetwork.ethBridge.inbox.toLowerCase()
        ) {
          providerOrSigner = this.novaSignerOrProvider;
          chainId = novaNetwork.chainID;
        } else {
          throw new Error(`Unknown inbox: ${e.bridgeMessageEvent.inbox}`);
        }

        const messageParser = new SubmitRetryableMessageDataParser();
        const inboxMessageData = messageParser.parse(e.inboxMessageEvent.data);
        const message = L1ToL2Message.fromEventComponents(
          providerOrSigner,
          chainId,
          e.bridgeMessageEvent.sender,
          e.inboxMessageEvent.messageNum,
          e.bridgeMessageEvent.baseFeeL1,
          inboxMessageData
        );

        proposalStages.push(new RetryableExecutionStage(message));
      }

      const l2Receipt = new L2TransactionReceipt(receipt);
      const l2ToL1Events =
        (await l2Receipt.getL2ToL1Events()) as EventArgs<NitroL2ToL1TransactionEvent>[];
      for (const e of l2ToL1Events) {
        proposalStages.push(
          new L1OutboxStage(e, this.l1SignerOrProvider, getProvider(this.arbOneSignerOrProvider)!)
        );
      }

      return proposalStages;
    } catch (err) {
      // CHRIS: TODO: remove this catch
      console.log(err);
      throw err;
    }
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
export interface TrackerEvent {
  identifier: string;
  status: ProposalStageStatus;
  stage: string;
  prevStage?: Omit<TrackerEvent, "status">;
  publicExecutionUrl?: string;
}
export interface TrackerErrorEvent extends TrackerEvent {
  error: Error;
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

  public emit(eventName: TrackerEventName.TRACKER_STARTED, args: TrackerEvent): boolean;
  public emit(eventName: TrackerEventName.TRACKER_ENDED, args: TrackerEvent): boolean;
  public emit(eventName: TrackerEventName.TRACKER_ERRORED, args: TrackerErrorEvent): boolean;
  public emit(eventName: TrackerEventName.TRACKER_STATUS, args: TrackerEvent): boolean;
  public override emit(eventName: TrackerEventName, args: TrackerEvent | TrackerErrorEvent) {
    return super.emit(eventName, args);
  }

  public on(
    eventName: TrackerEventName.TRACKER_STARTED,
    listener: (args: TrackerEvent) => void
  ): this;
  public on(
    eventName: TrackerEventName.TRACKER_ENDED,
    listener: (args: TrackerEvent) => void
  ): this;
  public on(
    eventName: TrackerEventName.TRACKER_ERRORED,
    listener: (args: TrackerErrorEvent) => void
  ): this;
  public on(
    eventName: TrackerEventName.TRACKER_STATUS,
    listener: (args: TrackerEvent) => void
  ): this;
  public override on(
    eventName: TrackerEventName,
    listener: ((args: TrackerEvent) => void) | ((args: TrackerErrorEvent) => void)
  ): this {
    return super.on(eventName, listener);
  }

  public async run() {
    let polling = true;
    let consecutiveErrors = 0;
    let currentStatus: ProposalStageStatus | undefined = undefined;

    while (polling) {
      try {
        const status = await this.stage.status();
        if (currentStatus !== status) {
          // emit an event if the status changes
          // CHRIS: TODO: add the other events

          this.emit(TrackerEventName.TRACKER_STATUS, {
            status,
            stage: this.stage.name,
            identifier: this.stage.identifier,
            publicExecutionUrl:
              status === ProposalStageStatus.EXECUTED
                ? await this.stage.getExecutionUrl()
                : undefined,
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
            const nextStages = await this.stageFactory.nextStages(execReceipt);

            for (const nStage of nextStages) {
              const tracker = new StageTracker(
                this.stageFactory,
                nStage,
                this.pollingIntervalMs,
                this.writeMode
              );

              // propagate events to the listener of this tracker - add some info about the previous stage
              tracker.on(TrackerEventName.TRACKER_STATUS, (args) => {
                this.emit(TrackerEventName.TRACKER_STATUS, {
                  ...args,
                  prevStage: args.prevStage || {
                    stage: this.stage.name,
                    identifier: this.stage.identifier,
                  },
                });
              });
              tracker.on(TrackerEventName.TRACKER_ENDED, (args) => {
                this.emit(TrackerEventName.TRACKER_ENDED, {
                  ...args,
                  prevStage: args.prevStage || {
                    stage: this.stage.name,
                    identifier: this.stage.identifier,
                  },
                });
              });
              tracker.on(TrackerEventName.TRACKER_STARTED, (args) => {
                this.emit(TrackerEventName.TRACKER_STARTED, {
                  ...args,
                  prevStage: args.prevStage || {
                    stage: this.stage.name,
                    identifier: this.stage.identifier,
                  },
                });
              });
              tracker.on(TrackerEventName.TRACKER_ERRORED, (args) => {
                this.emit(TrackerEventName.TRACKER_ERRORED, {
                  ...args,
                  prevStage: args.prevStage || {
                    stage: this.stage.name,
                    identifier: this.stage.identifier,
                  },
                });
              });
              // CHRIS: TODO: lets put all these together
              tracker.run();
            }

            // continue to the next stage - break the while loop
            polling = false;

            break;
          case ProposalStageStatus.PENDING:
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
  }
}
