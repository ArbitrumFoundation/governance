import {
  getL2Network,
  L1ToL2MessageStatus,
  L1ToL2MessageWriter,
  L1TransactionReceipt,
  L2ToL1MessageStatus,
  L2TransactionReceipt,
} from "@arbitrum/sdk";
import { Outbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Outbox__factory";
import { L2ToL1TxEvent as NitroL2ToL1TransactionEvent } from "@arbitrum/sdk/dist/lib/abi/ArbSys";
import { OutBoxTransactionExecutedEvent } from "@arbitrum/sdk/dist/lib/abi/Outbox";
import { EventArgs } from "@arbitrum/sdk/dist/lib/dataEntities/event";
import { TransactionReceipt } from "@ethersproject/providers";
import { BigNumber, constants, ethers, Signer } from "ethers";
import { defaultAbiCoder, hexDataLength, id } from "ethers/lib/utils";
import {
  ArbitrumTimelock__factory,
  L1ArbitrumTimelock__factory,
  L2ArbitrumGovernor__factory,
} from "../typechain-types";
import { CallScheduledEvent } from "../typechain-types/src/ArbitrumTimelock";
import { Inbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Inbox__factory";
import { wait } from "./utils";
import { EventEmitter } from "events";

/**
 * An execution stage of a proposal. Each stage can be executed, and results in a transaction receipt.
 * Proposal stages should be named by what happens during execution
 */
export interface ProposalStage {
  /**
   * Name of the stage
   */
  readonly name: string;
  /**
   * Identifying information of this stage instance. Used in error logging.
   */
  readonly identifier: string;
  /**
   * Current status of this stage
   */
  status(): Promise<ProposalStageStatus>;
  /**
   * Execute the current stage. Should only be called when status returns READY
   */
  execute(): Promise<void>;
  /**
   * The transaction receipt that was created during execution
   */
  getExecuteReceipt(): Promise<TransactionReceipt>;
}

/**
 * Error with additional proposal information
 */
class ProposalStageError extends Error {
  constructor(message: string, identifier: string, stageName: string, inner?: Error);
  constructor(
    message: string,
    public readonly identifier: string,
    public readonly stageName: string,
    public readonly inner?: Error
  ) {
    super(`[${stageName}:${identifier}] ${message}`);
    if (inner) {
      this.stack += "\nCaused By: " + inner.stack;
    }
  }
}

export class UnreachableCaseError extends Error {
  constructor(value: never) {
    super(`Unreachable case: ${value}`);
  }
}

/**
 * Taken from the GovernorTimelockUpgradeable solidity
 */
enum GovernorTimelockStatus {
  Pending = 0,
  Active = 1,
  Canceled = 2,
  Defeated = 3,
  Succeeded = 4,
  Queued = 5,
  Expired = 6,
  Executed = 7,
}

/**
 * A proposal stage is always in one of the following stages
 */
export enum ProposalStageStatus {
  /**
   * The proposal stage has not been executed, and is not yet ready to be executed
   */
  PENDING = 1,
  /**
   * Ready for execution
   */
  READY = 2,
  /**
   * The stage has already been executed
   */
  EXECUTED = 3,
  /**
   * The stage was terminated without execution
   */
  TERMINATED = 4,
}

/**
 * When a vote has passed, queue a proposal in the governor timelock
 */
export class GovernorQueueStage implements ProposalStage {
  public readonly name = "GovernorQueueStage";
  public readonly identifier: string;

  public constructor(
    public readonly proposalId: string,

    public readonly target: string,
    public readonly value: BigNumber,
    public readonly callData: string,
    public readonly description: string,

    public readonly governorAddress: string,
    public readonly signer: Signer
  ) {
    this.identifier = `${proposalId}:${target}:${value.toString()}:${callData}:${description}:${governorAddress}`;
  }

  public async status(): Promise<ProposalStageStatus> {
    const gov = L2ArbitrumGovernor__factory.connect(this.governorAddress, this.signer);

    const state = (await gov.state(this.proposalId)) as GovernorTimelockStatus;

    switch (state) {
      case GovernorTimelockStatus.Pending:
      case GovernorTimelockStatus.Active:
        return ProposalStageStatus.PENDING;
      case GovernorTimelockStatus.Succeeded:
        return ProposalStageStatus.READY;
      case GovernorTimelockStatus.Queued:
      case GovernorTimelockStatus.Executed:
        return ProposalStageStatus.EXECUTED;
      case GovernorTimelockStatus.Canceled:
      case GovernorTimelockStatus.Defeated:
      case GovernorTimelockStatus.Expired:
        return ProposalStageStatus.TERMINATED;
      default:
        throw new UnreachableCaseError(state);
    }
  }

  public async execute(): Promise<void> {
    const gov = L2ArbitrumGovernor__factory.connect(this.governorAddress, this.signer);

    await (
      await gov.functions.queue([this.target], [this.value], [this.callData], id(this.description))
    ).wait();
  }

  public async getExecuteReceipt(): Promise<TransactionReceipt> {
    const gov = L2ArbitrumGovernor__factory.connect(this.governorAddress, this.signer);

    const timelockAddress = await gov.timelock();
    const timelock = ArbitrumTimelock__factory.connect(timelockAddress, this.signer);
    const opId = await timelock.hashOperationBatch(
      [this.target],
      [this.value],
      [this.callData],
      constants.HashZero,
      id(this.description)
    );

    const callScheduledFilter = timelock.filters.CallScheduled(opId);

    const logs = await this.signer.provider!.getLogs({
      fromBlock: 0,
      toBlock: "latest",
      ...callScheduledFilter,
    });
    if (logs.length !== 1) {
      throw new ProposalStageError("Log length not 1", this.identifier, this.name);
    }

    return this.signer.provider!.getTransactionReceipt(logs[0].transactionHash);
  }
}

/**
 * When a timelock period has passed, execute the proposal action
 */
export class L2TimelockExecutionStage implements ProposalStage {
  public readonly name: string = "L2TimelockExecutionStage";
  public readonly identifier: string;

  public constructor(
    public readonly target: string,
    public readonly value: BigNumber,
    public readonly callData: string,
    public readonly description: string,

    public readonly timelockAddress: string,
    public readonly signer: Signer
  ) {
    this.identifier = `${target}:${value.toString()}:${callData}:${description}:${timelockAddress}`;
  }

  private operationBatchId: string = "";
  private async getHashOperationBatch() {
    if (!this.operationBatchId) {
      const timelock = ArbitrumTimelock__factory.connect(this.timelockAddress, this.signer);

      this.operationBatchId = await timelock.hashOperationBatch(
        [this.target],
        [this.value],
        [this.callData],
        constants.HashZero,
        id(this.description)
      );
    }
    return this.operationBatchId;
  }

  public async status(): Promise<ProposalStageStatus> {
    const timelock = ArbitrumTimelock__factory.connect(this.timelockAddress, this.signer);

    const operationId = await this.getHashOperationBatch();

    // operation was cancelled if it doesn't exist
    const exists = await timelock.isOperation(operationId);
    if (!exists) return ProposalStageStatus.TERMINATED;

    // if it does exist it should be in one of the following states
    // check isOperationReady before pending because pending is a super set of ready
    const ready = await timelock.isOperationReady(operationId);
    if (ready) return ProposalStageStatus.READY;
    const pending = await timelock.isOperationPending(operationId);
    if (pending) return ProposalStageStatus.PENDING;
    const done = await timelock.isOperationDone(operationId);
    if (done) return ProposalStageStatus.EXECUTED;

    throw new ProposalStageError(
      `Proposal exists in unexpected state: ${operationId}`,
      this.identifier,
      this.name
    );
  }

  public async execute(): Promise<void> {
    const timelock = ArbitrumTimelock__factory.connect(this.timelockAddress, this.signer);

    const tx = await timelock.functions.executeBatch(
      [this.target],
      [this.value],
      [this.callData],
      constants.HashZero,
      id(this.description)
    );

    await tx.wait();
  }

  public async getExecuteReceipt(): Promise<TransactionReceipt> {
    const timelock = ArbitrumTimelock__factory.connect(this.timelockAddress, this.signer);
    const operationId = await this.getHashOperationBatch();
    const callExecutedFilter = timelock.filters.CallExecuted(operationId);
    const logs = await this.signer.provider!.getLogs({
      fromBlock: 0,
      toBlock: "latest",
      ...callExecutedFilter,
    });

    if (logs.length !== 1) {
      throw new ProposalStageError(`Logs length not 1: ${logs.length}`, this.identifier, this.name);
    }

    return await this.signer.provider!.getTransactionReceipt(logs[0].transactionHash);
  }
}

/**
 * When a outbox entry is ready for execution, execute it
 */
export class L1OutboxStage implements ProposalStage {
  public name: string = "L1OutboxStage";
  public readonly identifier: string;

  public constructor(
    public readonly l2ExecutionReceipt: TransactionReceipt,
    public readonly l1Signer: Signer,
    public readonly l2Provider: ethers.providers.Provider
  ) {
    this.identifier = l2ExecutionReceipt.transactionHash;
  }

  public async status(): Promise<ProposalStageStatus> {
    const l2Receipt = new L2TransactionReceipt(this.l2ExecutionReceipt);

    const messages = await l2Receipt.getL2ToL1Messages(this.l1Signer);
    if (messages.length !== 1) {
      throw new ProposalStageError(
        `Message length not 1: ${messages.length}`,
        this.identifier,
        this.name
      );
    }

    const status = await messages[0].status(this.l2Provider);

    switch (status) {
      case L2ToL1MessageStatus.UNCONFIRMED:
        return ProposalStageStatus.PENDING;
      case L2ToL1MessageStatus.CONFIRMED:
        return ProposalStageStatus.READY;
      case L2ToL1MessageStatus.EXECUTED:
        return ProposalStageStatus.EXECUTED;
      default:
        throw new UnreachableCaseError(status);
    }
  }

  public async execute(): Promise<void> {
    const l2Receipt = new L2TransactionReceipt(this.l2ExecutionReceipt);

    const messages = await l2Receipt.getL2ToL1Messages(this.l1Signer);
    if (messages.length !== 1) {
      throw new ProposalStageError(
        `Message length not 1: ${messages.length}`,
        this.identifier,
        this.name
      );
    }
    await (await messages[0].execute(this.l2Provider)).wait();
  }

  public async getExecuteReceipt(): Promise<TransactionReceipt> {
    const l2Receipt = new L2TransactionReceipt(this.l2ExecutionReceipt);

    // we know this is a post nitro event
    const events = (await l2Receipt.getL2ToL1Events()) as EventArgs<NitroL2ToL1TransactionEvent>[];
    if (events.length !== 1) {
      throw new ProposalStageError(
        `Events length not 1: ${events.length}`,
        this.identifier,
        this.name
      );
    }
    const event = events[0];

    const l2Network = await getL2Network(this.l2Provider);
    const outbox = Outbox__factory.connect(l2Network.ethBridge.outbox, this.l1Signer.provider!);
    const outboxTxFilter = outbox.filters.OutBoxTransactionExecuted(
      // the to needs to be decoded, how do we do that?
      // we can look at the l2 to l1 tx
      event.destination,
      event.caller
    );

    const allEvents = await this.l1Signer.provider!.getLogs({
      fromBlock: 0,
      toBlock: "latest",
      ...outboxTxFilter,
    });

    const outboxEvents = allEvents.filter((e) =>
      (
        outbox.interface.parseLog(e).args as OutBoxTransactionExecutedEvent["args"]
      ).transactionIndex.eq(event.position)
    );

    if (outboxEvents.length !== 1) {
      throw new ProposalStageError(
        `Outbox events length not 1: ${outboxEvents.length}`,
        this.identifier,
        this.name
      );
    }

    return this.l1Signer.provider!.getTransactionReceipt(outboxEvents[0].transactionHash);
  }
}

/**
 * When an l1 timelock period has passed, execute the proposal action or create a retryable ticket
 */
export class L1TimelockExecutionStage implements ProposalStage {
  public name: string = "L1TimelockExecutionStage";
  public readonly identifier: string;

  public constructor(
    public readonly scheduleTxReceipt: TransactionReceipt,
    public readonly proposalDescription: string,
    public readonly l1Signer: Signer
  ) {
    this.identifier = `${this.scheduleTxReceipt.transactionHash}:${proposalDescription}`;
  }

  private getCallScheduledLog() {
    const iL1ArbTimelock = L1ArbitrumTimelock__factory.createInterface();
    const callScheduledLogs = this.scheduleTxReceipt.logs.filter(
      (l) => l.topics[0] === iL1ArbTimelock.getEventTopic("CallScheduled")
    );

    if (callScheduledLogs.length !== 1) {
      throw new ProposalStageError(
        `Missing CallScheduled event: ${callScheduledLogs.length}`,
        this.name,
        this.identifier
      );
    }
    return callScheduledLogs[0];
  }

  public async status(): Promise<ProposalStageStatus> {
    const iL1ArbTimelock = L1ArbitrumTimelock__factory.createInterface();
    const callScheduledLog = await this.getCallScheduledLog();
    const operationId = (
      iL1ArbTimelock.parseLog(callScheduledLog).args as CallScheduledEvent["args"]
    ).id;
    const timelockAddress = callScheduledLog.address;
    const timelock = L1ArbitrumTimelock__factory.connect(timelockAddress, this.l1Signer);

    // operation was cancelled if it doesn't exist
    const exists = await timelock.isOperation(operationId);
    if (!exists) return ProposalStageStatus.TERMINATED;

    // if it does exist it should be in one of the following states
    // check isOperationReady before pending because pending is a super set of ready
    const ready = await timelock.isOperationReady(operationId);
    if (ready) return ProposalStageStatus.READY;
    const pending = await timelock.isOperationPending(operationId);
    if (pending) return ProposalStageStatus.PENDING;
    const done = await timelock.isOperationDone(operationId);
    if (done) return ProposalStageStatus.EXECUTED;

    throw new ProposalStageError(
      `Proposal exists in unexpected state: ${operationId}`,
      this.identifier,
      this.name
    );
  }

  public async execute(): Promise<void> {
    const iL1ArbTimelock = L1ArbitrumTimelock__factory.createInterface();
    const callScheduledLog = await this.getCallScheduledLog();
    const callScheduledArgs = iL1ArbTimelock.parseLog(callScheduledLog)
      .args as CallScheduledEvent["args"];
    const timelockAddress = callScheduledLog.address;
    const timelock = L1ArbitrumTimelock__factory.connect(timelockAddress, this.l1Signer);

    const retryableMagic = await timelock.RETRYABLE_TICKET_MAGIC();
    let value = callScheduledArgs.value;
    if (callScheduledArgs.target.toLowerCase() === retryableMagic.toLowerCase()) {
      const parsedData = defaultAbiCoder.decode(
        ["address", "address", "uint256", "uint256", "uint256", "bytes"],
        callScheduledArgs.data
      );
      const inboxAddress = parsedData[0] as string;
      const innerValue = parsedData[2] as BigNumber;
      const innerGasLimit = parsedData[3] as BigNumber;
      const innerMaxFeePerGas = parsedData[4] as BigNumber;
      const innerData = parsedData[5] as string;

      const inbox = Inbox__factory.connect(inboxAddress, this.l1Signer.provider!);
      const submissionFee = await inbox.callStatic.calculateRetryableSubmissionFee(
        hexDataLength(innerData),
        0
      );

      const timelockBalance = await this.l1Signer.provider!.getBalance(timelockAddress);
      if (timelockBalance.lt(innerValue)) {
        throw new ProposalStageError(
          `Timelock does not contain enough balance to cover l2 value: ${timelockBalance.toString()} : ${innerValue.toString()}`,
          this.identifier,
          this.name
        );
      }

      // enough value to create a retryable ticket = submission fee + gas
      // the l2value needs to already be in the contract
      value = submissionFee
        .mul(2) // add some leeway for the base fee to increase
        .add(innerGasLimit.mul(innerMaxFeePerGas));
    }

    await (
      await timelock.functions.execute(
        callScheduledArgs.target,
        callScheduledArgs.value,
        callScheduledArgs.data,
        constants.HashZero,
        id(this.proposalDescription),
        { value: value }
      )
    ).wait();
  }

  public async getExecuteReceipt(): Promise<TransactionReceipt> {
    const iL1ArbTimelock = L1ArbitrumTimelock__factory.createInterface();
    const callScheduledLog = await this.getCallScheduledLog();
    const operationId = (
      iL1ArbTimelock.parseLog(callScheduledLog).args as CallScheduledEvent["args"]
    ).id;
    const timelockAddress = callScheduledLog.address;
    const timelock = L1ArbitrumTimelock__factory.connect(timelockAddress, this.l1Signer);

    const callExecutedFilter = timelock.filters.CallExecuted(operationId);
    const logs = await this.l1Signer.provider!.getLogs({
      fromBlock: 0,
      toBlock: "latest",
      ...callExecutedFilter,
    });

    if (logs.length !== 1) {
      throw new ProposalStageError(
        `CallExecuted logs length not 1: ${logs.length}`,
        this.identifier,
        this.name
      );
    }

    return await this.l1Signer.provider!.getTransactionReceipt(logs[0].transactionHash);
  }
}

/**
 * When a retryable ticket has been created, manually execute it
 */
export class RetryableExecutionStage implements ProposalStage {
  public readonly identifier: string;

  constructor(
    public readonly l2Signer: Signer,
    public readonly l1TransactionReceipt: TransactionReceipt
  ) {
    this.identifier = l1TransactionReceipt.transactionHash;
  }

  public name: string = "RetryableExecutionStage";

  private async getMessage(): Promise<L1ToL2MessageWriter> {
    const l1txReceipt = new L1TransactionReceipt(this.l1TransactionReceipt);

    const messages = await l1txReceipt.getL1ToL2Messages(this.l2Signer);

    if (messages.length !== 1) {
      throw new ProposalStageError(
        `L1 to L2 message length not 1: ${messages.length}`,
        this.identifier,
        this.name
      );
    }

    return messages[0];
  }

  public async status(): Promise<ProposalStageStatus> {
    const message = await this.getMessage();
    const msgStatus = await message.status();

    switch (msgStatus) {
      case L1ToL2MessageStatus.CREATION_FAILED:
        throw new ProposalStageError("Retryable creation failed", this.identifier, this.name);
      case L1ToL2MessageStatus.EXPIRED:
        throw new ProposalStageError("Retryable ticket expired", this.identifier, this.name);
      case L1ToL2MessageStatus.FUNDS_DEPOSITED_ON_L2:
        return ProposalStageStatus.READY;
      case L1ToL2MessageStatus.NOT_YET_CREATED:
        return ProposalStageStatus.PENDING;
      case L1ToL2MessageStatus.REDEEMED:
        return ProposalStageStatus.EXECUTED;
    }
  }

  public async execute(): Promise<void> {
    const message = await this.getMessage();

    await (await message.redeem()).wait();
  }

  public async getExecuteReceipt(): Promise<TransactionReceipt> {
    const message = await this.getMessage();

    const redeemResult = await message.getSuccessfulRedeem();

    if (redeemResult.status !== L1ToL2MessageStatus.REDEEMED) {
      throw new ProposalStageError(
        `Unexpected redeem result: ${redeemResult}`,
        this.identifier,
        this.name
      );
    }

    return redeemResult.l2TxReceipt;
  }
}

/**
 * A proposal stage pipeline. Describes the different stages a proposal must go through,
 * and links them together in an ordered pipeline.
 */
export type ProposalStagePipeline = AsyncGenerator<ProposalStage, void, unknown>;

export interface ProposalStagePipelineFactory {
  createPipeline(
    governorAddress: string,
    proposalId: string,
    target: string,
    value: BigNumber,
    callData: string,
    description: string
  ): ProposalStagePipeline;
}

/**
 * The round trip pipelines starts on ArbOne, moves through a timelock there,
 * withdraws to L1 and moves through a timelock there. From there it is either
 * executed directly on L1, or send in a retryable ticket to either Arb One or Nova
 * to be executed.
 **/
export class RoundTripProposalPipelineFactory implements ProposalStagePipelineFactory {
  constructor(
    readonly arbOneSigner: Signer,
    readonly l1Signer: Signer,
    readonly novaSigner: Signer
  ) {}

  public async *createPipeline(
    governorAddress: string,
    proposalId: string,
    target: string,
    value: BigNumber,
    callData: string,
    description: string
  ): ProposalStagePipeline {
    try {
      const govQueue = new GovernorQueueStage(
        proposalId,
        target,
        value,
        callData,
        description,
        governorAddress,
        this.arbOneSigner
      );
      yield govQueue;

      const timelock = await L2ArbitrumGovernor__factory.connect(
        governorAddress,
        this.arbOneSigner
      ).callStatic.timelock();
      const l2TimelockExecute = new L2TimelockExecutionStage(
        target,
        value,
        callData,
        description,
        timelock,
        this.arbOneSigner
      );
      yield l2TimelockExecute;

      const l2TimelockExecuteReceipt = await l2TimelockExecute.getExecuteReceipt();
      const l1OutboxExecute = new L1OutboxStage(
        l2TimelockExecuteReceipt,
        this.l1Signer,
        this.arbOneSigner.provider!
      );
      yield l1OutboxExecute;

      const outboxExecuteReceipt = await l1OutboxExecute.getExecuteReceipt();
      const l1TimelockExecute = new L1TimelockExecutionStage(
        outboxExecuteReceipt,
        description,
        this.l1Signer
      );
      yield l1TimelockExecute;

      const l1TimelockExecuteReceipt = await l1TimelockExecute.getExecuteReceipt();
      const l1txReceipt = new L1TransactionReceipt(l1TimelockExecuteReceipt);

      const l1ToL2Events = await l1txReceipt.getMessageEvents();
      if (l1ToL2Events.length > 0) {
        if (l1ToL2Events.length > 1) {
          throw new Error(`More than 1 l1 to l2 events: ${l1ToL2Events.length}`);
        }
        const inbox = l1ToL2Events[0].bridgeMessageEvent.inbox.toLowerCase();
        // find the relevant inbox
        const arbOneNetwork = await getL2Network(this.arbOneSigner);
        const novaNetwork = await getL2Network(this.novaSigner);

        if (arbOneNetwork.ethBridge.inbox.toLowerCase() === inbox) {
          yield new RetryableExecutionStage(this.arbOneSigner, l1TimelockExecuteReceipt);
        } else if (novaNetwork.ethBridge.inbox.toLowerCase() === inbox) {
          yield new RetryableExecutionStage(this.novaSigner, l1TimelockExecuteReceipt);
        } else throw new Error(`Inbox doesn't match any networks: ${inbox}`);
      }
    } catch (err) {
      const error = err as Error;
      throw new ProposalStageError(
        "Unexpected error in stage generation",
        `${proposalId}:${target}:${value.toString()}:${callData}:${description}:${governorAddress}`,
        "Generator",
        error
      );
    }
  }
}

/**
 * Follows a specific proposal, tracking it through its different stages
 * Executes each stage when it reaches READY, and exits upon observing a TERMINATED stage
 * Emits a "status" event when a new stage begins, or the status of a stage changes
 */
export class ProposalStageTracker extends EventEmitter {
  constructor(
    private readonly pipeline: ProposalStagePipeline,
    public readonly pollingIntervalMs: number
  ) {
    super();
  }

  public override emit(
    eventName: "status",
    args: {
      status: ProposalStageStatus;
      stage: string;
      identifier: string;
    }
  ) {
    return super.emit(eventName, args);
  }

  public override on(
    eventName: "status",
    listener: (args: { status: ProposalStageStatus; stage: string; identifier: string }) => void
  ) {
    return super.on(eventName, listener);
  }

  public async run() {
    for await (const stage of this.pipeline) {
      let polling = true;
      let consecutiveErrors = 0;
      let currentStatus: ProposalStageStatus | undefined = undefined;

      while (polling) {
        try {
          const status = await stage.status();
          if (currentStatus !== status) {
            // emit an event if the status changes
            this.emit("status", {
              status,
              stage: stage.name,
              identifier: stage.identifier,
            });
            currentStatus = status;
          }
          switch (status) {
            case ProposalStageStatus.TERMINATED:
              // end of the road
              return;
            case ProposalStageStatus.EXECUTED:
              // continue to the next stage - break the while loop
              polling = false;
              break;
            case ProposalStageStatus.PENDING:
              // keep checking status
              await wait(this.pollingIntervalMs);
              break;
            case ProposalStageStatus.READY:
              // ready, so execute
              await stage.execute();

              // sanity check
              const doneStatus = await stage.status();
              if (doneStatus !== ProposalStageStatus.EXECUTED) {
                throw new ProposalStageError(
                  "Stage executed but did not result in status 'EXECUTED'.",
                  stage.identifier,
                  stage.name
                );
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
            throw new ProposalStageError("Consecutive error", stage.identifier, stage.name, error);
          }

          await wait(this.pollingIntervalMs);
        }
      }
    }
  }
}
