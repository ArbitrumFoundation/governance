import {
  getL2Network,
  L1ToL2Message,
  L1ToL2MessageReader,
  L1ToL2MessageStatus,
  L1ToL2MessageWriter,
  L1TransactionReceipt,
  L2ToL1Message,
  L2ToL1MessageStatus,
  L2TransactionReceipt,
} from "@arbitrum/sdk";
import { Outbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Outbox__factory";
import { L2ToL1TxEvent as NitroL2ToL1TransactionEvent } from "@arbitrum/sdk/dist/lib/abi/ArbSys";
import { OutBoxTransactionExecutedEvent } from "@arbitrum/sdk/dist/lib/abi/Outbox";
import { TransactionReceipt } from "@ethersproject/providers";
import { BigNumber, constants, ethers, providers, Signer } from "ethers";
import { defaultAbiCoder, hexDataLength, id, keccak256 } from "ethers/lib/utils";
import {
  ArbitrumTimelock__factory,
  L1ArbitrumTimelock__factory,
  L2ArbitrumGovernor__factory,
  GovernorUpgradeable__factory,
  SecurityCouncilNomineeElectionGovernor__factory,
  ArbSys__factory,
} from "../typechain-types";
import { Inbox__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Inbox__factory";
import { EventArgs } from "@arbitrum/sdk/dist/lib/dataEntities/event";
import { InboxMessageKind } from "@arbitrum/sdk/dist/lib/dataEntities/message";
import { SubmitRetryableMessageDataParser } from "@arbitrum/sdk/dist/lib/message/messageDataParser";
import { BridgeCallTriggeredEventObject } from "../typechain-types/@arbitrum/nitro-contracts/src/bridge/IBridge";
import { Bridge__factory } from "@arbitrum/sdk/dist/lib/abi/factories/Bridge__factory";
import {
  ProposalCreatedEventObject,
  ProposalExecutedEventObject,
  ProposalQueuedEventObject,
} from "../typechain-types/src/L2ArbitrumGovernor";
import { hasTimelock, hasVettingPeriod, getL1BlockNumberFromL2 } from "./utils";
import { CallScheduledEvent } from "../typechain-types/src/ArbitrumTimelock";
import { GnosisSafeL2__factory } from "../types/ethers-contracts/factories/GnosisSafeL2__factory";

type Provider = providers.Provider;

export function isSigner(signerOrProvider: Signer | Provider): signerOrProvider is Signer {
  return (signerOrProvider as Signer).signMessage != undefined;
}
export function getProvider(signerOrProvider: Signer | Provider): Provider | undefined {
  return isSigner(signerOrProvider) ? signerOrProvider.provider : signerOrProvider;
}

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
  /**
   * An etherscan url for the execution receipt. Only available for mainnet transactions
   */
  getExecutionUrl(): Promise<string | undefined>;
}

/**
 * Error with additional proposal information
 */
export class ProposalStageError extends Error {
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
 * Taken from the IGovernorUpgradeable solidity
 */
enum ProposalState {
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
   * Proposal stage is still not ready to be executed, but has transitioned to a new state;
   * e.g, for a Governor, ACTIVE signifies that users can vote. For other proposals, there is no
   * ACTIVE stage, and the proposal will go directly from PENDING to READY
   */

  ACTIVE = 2,

  /**
   * Ready for execution
   */

  READY = 3,
  /**
   * The stage has already been executed
   */
  EXECUTED = 4,
  /**
   * The stage was terminated without execution
   */
  TERMINATED = 5,
}

/**
 * Governor with no timelock and no vetting period (i.e., SecurityCouncilMemberElectionGovernor)
 */
export class BaseGovernorExecuteStage implements ProposalStage {
  public readonly identifier: string;

  public constructor(
    public readonly targets: string[],
    public readonly values: BigNumber[],
    public readonly callDatas: string[],
    public readonly description: string,
    public readonly startBlock: BigNumber,
    public readonly governorAddress: string,
    public readonly signerOrProvider: Signer | providers.Provider
  ) {
    this.identifier = keccak256(
      defaultAbiCoder.encode(
        ["address[]", "uint256[]", "bytes[]", "bytes32"],
        [targets, values, callDatas, id(description)]
      )
    );
  }

  public get name() {
    return "BaseGovernorExecuteStage";
  }

  public get governor() {
    return GovernorUpgradeable__factory.connect(this.governorAddress, this.signerOrProvider);
  }

  public quorum() {
    try {
      return L2ArbitrumGovernor__factory.connect(
        this.governorAddress,
        this.signerOrProvider
      ).quorum(this.startBlock);
    } catch (err) {
      console.log("Error: could not get quorum", err);
    }
  }

  /**
   * Extract and instantiate appropriate governor proposal stage
   */
  public static async extractStages(
    receipt: TransactionReceipt,
    arbOneSignerOrProvider: Provider | Signer
  ): Promise<BaseGovernorExecuteStage[]> {
    const govInterface = L2ArbitrumGovernor__factory.createInterface();
    const proposalStages: BaseGovernorExecuteStage[] = [];
    for (const log of receipt.logs) {
      if (log.topics.find((t) => t === govInterface.getEventTopic("ProposalCreated"))) {
        const propCreatedEvent = govInterface.parseLog(log)
          .args as unknown as ProposalCreatedEventObject;
        if (await hasTimelock(log.address, getProvider(arbOneSignerOrProvider)!)) {
          proposalStages.push(
            new GovernorQueueStage(
              propCreatedEvent.targets,
              (propCreatedEvent as any)[3], // ethers is parsing an array with a single 0 big number as undefined, so we lookup by index
              propCreatedEvent.calldatas,
              propCreatedEvent.description,
              propCreatedEvent.startBlock,
              log.address,
              arbOneSignerOrProvider
            )
          );
        } else if (await hasVettingPeriod(log.address, getProvider(arbOneSignerOrProvider)!)) {
          proposalStages.push(
            new GovernorWithVetterExecuteStage(
              propCreatedEvent.targets,
              (propCreatedEvent as any)[3], // ethers is parsing an array with a single 0 big number as undefined, so we lookup by index
              propCreatedEvent.calldatas,
              propCreatedEvent.description,
              propCreatedEvent.startBlock,
              log.address,
              arbOneSignerOrProvider
            )
          );
        } else {
          proposalStages.push(
            new BaseGovernorExecuteStage(
              propCreatedEvent.targets,
              (propCreatedEvent as any)[3], // ethers is parsing an array with a single 0 big number as undefined, so we lookup by index
              propCreatedEvent.calldatas,
              propCreatedEvent.description,
              propCreatedEvent.startBlock,
              log.address,
              arbOneSignerOrProvider
            )
          );
        }
      }
    }

    return proposalStages;
  }

  public async status(): Promise<ProposalStageStatus> {
    const state = (await this.governor.state(this.identifier)) as ProposalState;
    switch (state) {
      case ProposalState.Pending:
        return ProposalStageStatus.PENDING;
      case ProposalState.Active:
        return ProposalStageStatus.ACTIVE;
      case ProposalState.Succeeded:
        return ProposalStageStatus.READY;
      case ProposalState.Queued:
      case ProposalState.Executed:
        return ProposalStageStatus.EXECUTED;
      case ProposalState.Canceled:
      case ProposalState.Defeated:
      case ProposalState.Expired:
        return ProposalStageStatus.TERMINATED;
      default:
        throw new UnreachableCaseError(state);
    }
  }

  public async execute(): Promise<void> {
    await (
      await this.governor.functions.execute(
        this.targets,
        this.values,
        this.callDatas,
        id(this.description)
      )
    ).wait();
  }

  public async getExecuteReceipt(): Promise<TransactionReceipt> {
    const govInterface = GovernorUpgradeable__factory.createInterface();

    const proposalExecutedFilter = this.governor.filters.ProposalExecuted();
    const provider = getProvider(this.signerOrProvider);

    const logs = await provider!.getLogs({
      fromBlock: 0,
      toBlock: "latest",
      ...proposalExecutedFilter,
    });
    for (let log of logs) {
      const eventObject = govInterface.parseLog(log).args as unknown as ProposalExecutedEventObject;
      if (eventObject.proposalId.toHexString() == this.identifier) {
        return await provider!.getTransactionReceipt(log.transactionHash);
      }
    }
    throw new ProposalStageError("Execution event not found", this.identifier, this.name);
  }

  public async getExecutionUrl(): Promise<string | undefined> {
    const execReceipt = await this.getExecuteReceipt();
    return `https://arbiscan.io/tx/${execReceipt.transactionHash}`;
  }
}

export class GovernorWithVetterExecuteStage extends BaseGovernorExecuteStage {
  public get name() {
    return "GovernorWithVetterExecuteStage";
  }

  public get governor() {
    return SecurityCouncilNomineeElectionGovernor__factory.connect(
      this.governorAddress,
      this.signerOrProvider
    );
  }

  public async status(): Promise<ProposalStageStatus> {
    // If governor status returns "ready", check if in vetting period
    const status = await super.status();
    if (status == ProposalStageStatus.READY) {
      const vettingDeadline = await this.governor.proposalVettingDeadline(this.identifier);
      const blockNumber = await getL1BlockNumberFromL2(getProvider(this.signerOrProvider)!);
      if (blockNumber.lte(vettingDeadline)) {
        return ProposalStageStatus.PENDING;
      }
    }
    return status;
  }
}

/**
 * When a vote has passed, queue a proposal in the governor timelock
 */
export class GovernorQueueStage extends BaseGovernorExecuteStage {
  public get name() {
    return "GovernorQueueStage";
  }

  public get governor() {
    return L2ArbitrumGovernor__factory.connect(this.governorAddress, this.signerOrProvider);
  }

  /**
   * Execute on timelock
   */
  public async execute(): Promise<void> {
    await (
      await this.governor.functions.queue(
        this.targets,
        this.values,
        this.callDatas,
        id(this.description)
      )
    ).wait();
  }

  public async getExecuteReceipt(): Promise<TransactionReceipt> {
    const timelockAddress = await this.governor.timelock();
    const timelock = ArbitrumTimelock__factory.connect(timelockAddress, this.signerOrProvider);
    const opId = await timelock.hashOperationBatch(
      this.targets,
      this.values,
      this.callDatas,
      constants.HashZero,
      id(this.description)
    );

    const callScheduledFilter = timelock.filters.CallScheduled(opId);
    const provider = getProvider(this.signerOrProvider);

    const logs = await provider!.getLogs({
      fromBlock: 0,
      toBlock: "latest",
      ...callScheduledFilter,
    });
    if (logs.length !== 1) {
      throw new ProposalStageError("Log length not 1", this.identifier, this.name);
    }

    return await provider!.getTransactionReceipt(logs[0].transactionHash);
  }
}

abstract class L2TimelockExecutionStage implements ProposalStage {
  public readonly identifier: string;

  constructor(
    public readonly name: string,
    public readonly operationId: string,
    public readonly timelockAddress: string,
    public readonly signerOrProvider: Signer | Provider
  ) {
    this.identifier = operationId;
  }

  public static async getProposalCreatedData(
    governor: string,
    proposalId: string,
    provider: Provider,
    startBlock: number,
    endBlock: number
  ): Promise<ProposalCreatedEventObject | undefined> {
    const govInterface = L2ArbitrumGovernor__factory.createInterface();
    const filterTopics = govInterface.encodeFilterTopics("ProposalCreated", []);

    const logs = await provider.getLogs({
      fromBlock: startBlock,
      toBlock: endBlock,
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

  /**
   * Find the timelock address - it is the address from which CallScheduled events are emitted
   */
  public static findTimelockAddress(operationId: string, logs: ethers.providers.Log[]) {
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

  public static hashOperation(
    target: string,
    value: BigNumber,
    callData: string,
    predecessor: string,
    salt: string
  ) {
    return keccak256(
      defaultAbiCoder.encode(
        ["address", "uint256", "bytes", "bytes32", "bytes32"],
        [target, value, callData, predecessor, salt]
      )
    );
  }

  public static decodeSchedule(data: string) {
    const iFace = ArbitrumTimelock__factory.createInterface();
    const decodeRes = iFace.decodeFunctionData("schedule", data);
    return {
      target: decodeRes[0] as string,
      value: decodeRes[1] as BigNumber,
      callData: decodeRes[2] as string,
      predecessor: decodeRes[3] as string,
      salt: decodeRes[4] as string,
    };
  }

  public static hashOperationBatch(
    targets: string[],
    values: BigNumber[],
    callDatas: string[],
    predecessor: string,
    salt: string
  ) {
    return keccak256(
      defaultAbiCoder.encode(
        ["address[]", "uint256[]", "bytes[]", "bytes32", "bytes32"],
        [targets, values, callDatas, predecessor, salt]
      )
    );
  }

  public static decodeScheduleBatch(data: string) {
    const iFace = ArbitrumTimelock__factory.createInterface();
    const decodeRes = iFace.decodeFunctionData("scheduleBatch", data);
    return {
      targets: decodeRes[0] as string[],
      values: decodeRes[1] as BigNumber[],
      callDatas: decodeRes[2] as string[],
      predecessor: decodeRes[3] as string,
      salt: decodeRes[4] as string,
    };
  }

  public static async getL2SaltForProposalSubmittedOnTimelock(txHash: string, provider: Provider) {
    // We assume a proposal submitted directly on the timelock was from a Gnosis safe and attempt to
    // decode and extract the salt accordingly
    const txRes = await provider.getTransaction(txHash);
    const { data: execTxData } = GnosisSafeL2__factory.createInterface().decodeFunctionData(
      "execTransaction",
      txRes.data
    );
    try {
      return (await this.decodeScheduleBatch(execTxData)).salt;
    } catch (e) {
      return (await this.decodeSchedule(execTxData)).salt;
    }
  }

  public async status(): Promise<ProposalStageStatus> {
    const timelock = ArbitrumTimelock__factory.connect(this.timelockAddress, this.signerOrProvider);

    // operation was cancelled if it doesn't exist
    const exists = await timelock.isOperation(this.operationId);
    if (!exists) return ProposalStageStatus.TERMINATED;

    // if it does exist it should be in one of the following states
    // check isOperationReady before pending because pending is a super set of ready
    const ready = await timelock.isOperationReady(this.operationId);
    if (ready) return ProposalStageStatus.READY;
    const pending = await timelock.isOperationPending(this.operationId);
    if (pending) return ProposalStageStatus.PENDING;
    const done = await timelock.isOperationDone(this.operationId);
    if (done) return ProposalStageStatus.EXECUTED;

    throw new ProposalStageError(
      `Proposal exists in unexpected state: ${this.operationId}`,
      this.operationId,
      this.name
    );
  }

  public async getExecuteReceipt(): Promise<TransactionReceipt> {
    const timelock = ArbitrumTimelock__factory.connect(this.timelockAddress, this.signerOrProvider);
    const provider = getProvider(this.signerOrProvider);
    const callExecutedFilter = timelock.filters.CallExecuted(this.operationId);
    const logs = await provider!.getLogs({
      fromBlock: 0,
      toBlock: "latest",
      ...callExecutedFilter,
    });

    if (logs.length !== 1) {
      throw new ProposalStageError(`Logs length not 1: ${logs.length}`, this.identifier, this.name);
    }

    return await provider!.getTransactionReceipt(logs[0].transactionHash);
  }

  public async getExecutionUrl(): Promise<string> {
    const execReceipt = await this.getExecuteReceipt();
    return `https://arbiscan.io/tx/${execReceipt.transactionHash}`;
  }

  public abstract execute(): Promise<void>;
}

/**
 * When a timelock period has passed, execute the proposal action
 */
export class L2TimelockExecutionBatchStage extends L2TimelockExecutionStage {
  public constructor(
    public readonly targets: string[],
    public readonly values: BigNumber[],
    public readonly callDatas: string[],
    public readonly predecessor: string,
    public readonly salt: string,

    timelockAddress: string,
    signerOrProvider: Signer | Provider
  ) {
    const operationId = L2TimelockExecutionBatchStage.hashOperationBatch(
      targets,
      values,
      callDatas,
      predecessor,
      salt
    );
    super("L2TimelockExecutionBatchStage", operationId, timelockAddress, signerOrProvider);
  }

  public static async extractStages(
    receipt: TransactionReceipt,
    arbOneSignerOrProvider: Provider | Signer
  ): Promise<L2TimelockExecutionBatchStage[]> {
    const govInterface = L2ArbitrumGovernor__factory.createInterface();
    const proposalStages: L2TimelockExecutionBatchStage[] = [];
    const timelockInterface = ArbitrumTimelock__factory.createInterface();
    // ids of timelock operations for corresponing ProposalQueued operations found
    const timelockOperationIdsFound = new Set<string>();

    for (const log of receipt.logs) {
      if (log.topics.find((t) => t === govInterface.getEventTopic("ProposalQueued"))) {
        const propQueuedObj = govInterface.parseLog(log)
          .args as unknown as ProposalQueuedEventObject;

        // 10m ~ 1 month on arbitrum
        const propCreatedStart = log.blockNumber - 10000000;
        const propCreatedEnd = log.blockNumber;
        const propCreatedEvent = await this.getProposalCreatedData(
          log.address,
          propQueuedObj.proposalId.toHexString(),
          await getProvider(arbOneSignerOrProvider)!,
          propCreatedStart,
          propCreatedEnd
        );
        if (!propCreatedEvent) {
          throw new Error(
            `Could not find proposal created event: ${propQueuedObj.proposalId.toHexString()}`
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
          // if we couldnt find the timelock address it's because the operation id was not found on a callscheduled event
          // this could be because it was formed via batch instead of single, or vice versa, and is an expected result
          continue;
        }
        timelockOperationIdsFound.add(operationId);
        // we know the operation id
        const executeBatch = new L2TimelockExecutionBatchStage(
          propCreatedEvent.targets,
          (propCreatedEvent as any)[3],
          propCreatedEvent.calldatas,
          constants.HashZero,
          id(propCreatedEvent.description),
          timelockAddress,
          arbOneSignerOrProvider
        );
        proposalStages.push(executeBatch);
      }

      try {
        // get calls scheduled directly on timelock (not via gov)
        const callScheduledOnTimelock: CallScheduledEvent["args"][] = [];
        for (let log of receipt.logs) {
          const timelockLog = log.topics.find(
            (t) => t === timelockInterface.getEventTopic("CallScheduled")
          );
          if (!timelockLog) {
            continue;
          }
          const callScheduledArgs = timelockInterface.parseLog(log)
            .args as CallScheduledEvent["args"];
          // skip calls previously found scheduled via gov
          if (timelockOperationIdsFound.has(callScheduledArgs.id)) {
            continue;
          }
          callScheduledOnTimelock.push(callScheduledArgs);
        }

        const uniqueOperationIds = new Set(callScheduledOnTimelock.map((arg) => arg.id)).size;

        if (uniqueOperationIds == 1) {
          // we expect all operations to have the same id (i.e., part of the same batch)
          const targets = callScheduledOnTimelock.map((args) => args.target);
          const values = callScheduledOnTimelock.map((args) => args[3]);
          const datas = callScheduledOnTimelock.map((args) => args.data);
          const predecessor = callScheduledOnTimelock[0].predecessor;
          const salt = await this.getL2SaltForProposalSubmittedOnTimelock(
            receipt.transactionHash,
            await getProvider(arbOneSignerOrProvider)!
          );
          const operationId = this.hashOperationBatch(targets, values, datas, predecessor, salt);
          if (operationId !== callScheduledOnTimelock[0].id) {
            throw new Error("XXX Invalid operation id");
          }
          const timelockAddress = this.findTimelockAddress(operationId, receipt.logs);
          if (!timelockAddress) throw new Error("timelock address not found");
          const executeTimelock = new L2TimelockExecutionBatchStage(
            targets,
            values,
            datas,
            predecessor,
            salt,
            timelockAddress,
            arbOneSignerOrProvider
          );
          proposalStages.push(executeTimelock);
        } else if (uniqueOperationIds > 1) {
          // Multiple calls to scheduleBatch in a single tx is not supported
          throw new Error("Multiple batches in single tx");
        }
      } catch (err) {
        // there are expected errors since the calldata may not be of the expected form for decoding
        continue;
      }
    }

    return proposalStages;
  }

  public async execute(): Promise<void> {
    const timelock = ArbitrumTimelock__factory.connect(this.timelockAddress, this.signerOrProvider);
    const tx = await timelock.functions.executeBatch(
      this.targets,
      this.values,
      this.callDatas,
      this.predecessor,
      this.salt
    );

    await tx.wait();
  }
}

/**
 * When a timelock period has passed, execute the proposal action
 */
export class L2TimelockExecutionSingleStage extends L2TimelockExecutionStage {
  public constructor(
    public readonly target: string,
    public readonly value: BigNumber,
    public readonly callData: string,
    public readonly predecessor: string,
    public readonly salt: string,

    timelockAddress: string,
    signerOrProvider: Signer | Provider
  ) {
    const operationId = L2TimelockExecutionSingleStage.hashOperation(
      target,
      value,
      callData,
      predecessor,
      salt
    );
    super("L2TimelockExecutionSingleStage", operationId, timelockAddress, signerOrProvider);
  }

  public static async extractStages(
    receipt: TransactionReceipt,
    arbOneSignerOrProvider: Provider | Signer
  ): Promise<L2TimelockExecutionSingleStage[]> {
    const proposalStages: L2TimelockExecutionSingleStage[] = [];
    const govInterface = L2ArbitrumGovernor__factory.createInterface();
    const timelockInterface = ArbitrumTimelock__factory.createInterface();

    for (const log of receipt.logs) {
      if (log.topics[0] === timelockInterface.getEventTopic("CallScheduled")) {
        // try to parse the call scheduled event to get get the operation id and form as stage
        // the data should be a call to arbsys sendTxToL1
        try {
          const callScheduledArgs = timelockInterface.parseLog(log)
            .args as CallScheduledEvent["args"];

          const salt = await this.getL2SaltForProposalSubmittedOnTimelock(
            receipt.transactionHash,
            await getProvider(arbOneSignerOrProvider)!
          );

          // calculate the id and check if that operation exists
          const operationId = this.hashOperation(
            callScheduledArgs.target,
            callScheduledArgs[3], // cant use .value as ethers fails with this
            callScheduledArgs.data,
            callScheduledArgs.predecessor,
            salt
          );

          if (operationId !== callScheduledArgs.id) {
            throw new Error("Invalid operation id");
          }

          const timelockAddress = log.address;
          const executeTimelock = new L2TimelockExecutionSingleStage(
            callScheduledArgs.target,
            callScheduledArgs[3],
            callScheduledArgs.data,
            callScheduledArgs.predecessor,
            salt,
            timelockAddress,
            arbOneSignerOrProvider
          );
          if (
            proposalStages.filter((s) => s.identifier === executeTimelock.identifier).length === 0
          ) {
            proposalStages.push(executeTimelock);
          }
        } catch (err) {
          // there are expected errors since the calldata may not be of the expected form for decoding
          continue;
        }
      } else if (log.topics[0] === govInterface.getEventTopic("ProposalQueued")) {
        const proposalId = (
          govInterface.parseLog(log).args as unknown as ProposalQueuedEventObject
        ).proposalId.toHexString();

        // 10m ~ 1 month on arbitrum
        const propCreatedStart = log.blockNumber - 10000000;
        const propCreatedEnd = log.blockNumber;

        const propCreatedEvent = await this.getProposalCreatedData(
          log.address,
          proposalId,
          await getProvider(arbOneSignerOrProvider)!,
          propCreatedStart,
          propCreatedEnd
        );
        if (!propCreatedEvent) {
          throw new Error(`Could not find proposal created event: ${proposalId}`);
        }
        // calculate the operation id, and look for it in this receipt
        const operationId = L2TimelockExecutionSingleStage.hashOperation(
          propCreatedEvent.targets[0],
          (propCreatedEvent as any)[3][0],
          propCreatedEvent.calldatas[0],
          constants.HashZero,
          id(propCreatedEvent.description)
        );
        const timelockAddress = this.findTimelockAddress(operationId, receipt.logs);
        if (!timelockAddress) {
          // if we couldnt find the timelock address it's because the operation id was not found on a callscheduled event
          // this could be because it was formed via batch instead of single, or vice versa, and is an expected result
          continue;
        }
        const executeTimelock = new L2TimelockExecutionSingleStage(
          propCreatedEvent.targets[0],
          (propCreatedEvent as any)[3][0],
          propCreatedEvent.calldatas[0],
          constants.HashZero,
          id(propCreatedEvent.description),
          timelockAddress,
          arbOneSignerOrProvider
        );
        if (
          proposalStages.filter((s) => s.identifier === executeTimelock.identifier).length === 0
        ) {
          proposalStages.push(executeTimelock);
        }
      }
    }

    return proposalStages;
  }

  public async execute(): Promise<void> {
    const timelock = ArbitrumTimelock__factory.connect(this.timelockAddress, this.signerOrProvider);
    const tx = await timelock.functions.execute(
      this.target,
      this.value,
      this.callData,
      this.predecessor,
      this.salt
    );

    await tx.wait();
  }
}

/**
 * When a outbox entry is ready for execution, execute it
 */
export class L1OutboxStage implements ProposalStage {
  public name: string = "L1OutboxStage";
  public readonly identifier: string;

  public constructor(
    public readonly l2ToL1TxEvent: EventArgs<NitroL2ToL1TransactionEvent>,
    public readonly l1SignerOrProvider: Signer | Provider,
    public readonly l2Provider: ethers.providers.Provider
  ) {
    this.identifier = keccak256(
      defaultAbiCoder.encode(
        ["address", "uint256", "uint256"],
        [l2ToL1TxEvent.destination, l2ToL1TxEvent.hash, l2ToL1TxEvent.position]
      )
    );
  }

  public static async extractStages(
    receipt: TransactionReceipt,
    l1SignerOrProvider: Signer | Provider,
    arbOneProvider: ethers.providers.Provider
  ): Promise<L1OutboxStage[]> {
    const l2Receipt = new L2TransactionReceipt(receipt);
    const l2ToL1Events =
      (await l2Receipt.getL2ToL1Events()) as EventArgs<NitroL2ToL1TransactionEvent>[];

    return l2ToL1Events.map((e) => new L1OutboxStage(e, l1SignerOrProvider, arbOneProvider));
  }

  public async status(): Promise<ProposalStageStatus> {
    const message = L2ToL1Message.fromEvent(this.l1SignerOrProvider, this.l2ToL1TxEvent);
    const status = await message.status(this.l2Provider);

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
    if (!isSigner(this.l1SignerOrProvider)) throw new Error("Missing signer");
    const message = L2ToL1Message.fromEvent(this.l1SignerOrProvider, this.l2ToL1TxEvent);
    await (await message.execute(this.l2Provider)).wait();
  }

  public async getExecuteReceipt(): Promise<TransactionReceipt> {
    const event = this.l2ToL1TxEvent;

    const l2Network = await getL2Network(this.l2Provider);
    const provider = getProvider(this.l1SignerOrProvider);
    const outbox = Outbox__factory.connect(l2Network.ethBridge.outbox, provider!);
    const outboxTxFilter = outbox.filters.OutBoxTransactionExecuted(
      event.destination,
      event.caller
    );

    const allEvents = await provider!.getLogs({
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

    return provider!.getTransactionReceipt(outboxEvents[0].transactionHash);
  }

  public async getExecutionUrl(): Promise<string> {
    const execReceipt = await this.getExecuteReceipt();
    return `https://etherscan.io/tx/${execReceipt.transactionHash}`;
  }
}

abstract class L1TimelockExecutionStage {
  constructor(
    public readonly name: string,
    public readonly timelockAddress: string,
    public readonly l1SignerOrProvider: Signer | Provider,
    public readonly identifier: string
  ) {}

  public async status(): Promise<ProposalStageStatus> {
    const timelock = L1ArbitrumTimelock__factory.connect(
      this.timelockAddress,
      this.l1SignerOrProvider
    );

    // operation was cancelled if it doesn't exist
    const exists = await timelock.isOperation(this.identifier);
    if (!exists) return ProposalStageStatus.TERMINATED;

    // if it does exist it should be in one of the following states
    // check isOperationReady before pending because pending is a super set of ready
    const ready = await timelock.isOperationReady(this.identifier);
    if (ready) return ProposalStageStatus.READY;
    const pending = await timelock.isOperationPending(this.identifier);
    if (pending) return ProposalStageStatus.PENDING;
    const done = await timelock.isOperationDone(this.identifier);
    if (done) return ProposalStageStatus.EXECUTED;

    throw new ProposalStageError(
      `Proposal exists in unexpected state: ${this.identifier}`,
      this.identifier,
      this.name
    );
  }

  public async getExecutionValue(target: string, data: string): Promise<BigNumber | undefined> {
    const timelock = L1ArbitrumTimelock__factory.connect(
      this.timelockAddress,
      this.l1SignerOrProvider
    );
    const retryableMagic = await timelock.RETRYABLE_TICKET_MAGIC();
    if (target.toLowerCase() === retryableMagic.toLowerCase()) {
      const parsedData = defaultAbiCoder.decode(
        ["address", "address", "uint256", "uint256", "uint256", "bytes"],
        data
      );
      const inboxAddress = parsedData[0] as string;
      const innerValue = parsedData[2] as BigNumber;
      const innerGasLimit = parsedData[3] as BigNumber;
      const innerMaxFeePerGas = parsedData[4] as BigNumber;
      const innerData = parsedData[5] as string;
      const inbox = Inbox__factory.connect(inboxAddress, timelock.provider!);
      const submissionFee = await inbox.callStatic.calculateRetryableSubmissionFee(
        hexDataLength(innerData),
        0
      );

      // enough value to create a retryable ticket = submission fee + gas
      // the l2value needs to already be in the contract
      return submissionFee
        .mul(2) // add some leeway for the base fee to increase
        .add(innerGasLimit.mul(innerMaxFeePerGas))
        .add(innerValue);
    }
  }

  public async getExecuteReceipt(): Promise<TransactionReceipt> {
    const timelock = L1ArbitrumTimelock__factory.connect(
      this.timelockAddress,
      this.l1SignerOrProvider
    );
    const provider = getProvider(this.l1SignerOrProvider);
    const callExecutedFilter = timelock.filters.CallExecuted(this.identifier);

    const logs = await provider!.getLogs({
      fromBlock: 0,
      toBlock: "latest",
      ...callExecutedFilter,
    });

    if (logs.length < 1) {
      throw new ProposalStageError(
        `CallExecuted logs length not greater than 0: ${logs.length}`,
        this.identifier,
        this.name
      );
    }

    return await provider!.getTransactionReceipt(logs[0].transactionHash);
  }

  public async getExecutionUrl(): Promise<string> {
    const execReceipt = await this.getExecuteReceipt();
    return `https://etherscan.io/tx/${execReceipt.transactionHash}`;
  }
}

/**
 * When an l1 timelock period has passed, execute the proposal action
 */
export class L1TimelockExecutionSingleStage
  extends L1TimelockExecutionStage
  implements ProposalStage
{
  public constructor(
    timelockAddress: string,
    public readonly target: string,
    public readonly value: BigNumber,
    public readonly data: string,
    public readonly predecessor: string,
    public readonly salt: string,
    l1SignerOrProvider: Signer | Provider
  ) {
    super(
      "L1TimelockExecutionSingleStage",
      timelockAddress,
      l1SignerOrProvider,
      keccak256(
        defaultAbiCoder.encode(
          ["address", "uint256", "bytes", "bytes32", "bytes32"],
          [target, value, data, predecessor, salt]
        )
      )
    );
  }

  public static async extractStages(
    receipt: TransactionReceipt,
    l1SignerOrProvider: Signer | Provider
  ): Promise<L1TimelockExecutionSingleStage[]> {
    const timelockInterface = ArbitrumTimelock__factory.createInterface();
    const bridgeInterface = Bridge__factory.createInterface();
    const proposalStages: L1TimelockExecutionSingleStage[] = [];
    for (const log of receipt.logs) {
      if (log.topics.find((t) => t === bridgeInterface.getEventTopic("BridgeCallTriggered"))) {
        const bridgeCallTriggered = bridgeInterface.parseLog(log)
          .args as unknown as BridgeCallTriggeredEventObject;
        const funcSig = bridgeCallTriggered.data.slice(0, 10);

        const schedFunc =
          timelockInterface.functions["schedule(address,uint256,bytes,bytes32,bytes32,uint256)"];
        if (funcSig === timelockInterface.getSighash(schedFunc)) {
          const scheduleBatchData = L2TimelockExecutionBatchStage.decodeSchedule(
            bridgeCallTriggered.data
          );
          const operationId = L2TimelockExecutionBatchStage.hashOperation(
            scheduleBatchData.target,
            scheduleBatchData.value,
            scheduleBatchData.callData,
            scheduleBatchData.predecessor,
            scheduleBatchData.salt
          );
          const timelockAddress = L2TimelockExecutionBatchStage.findTimelockAddress(
            operationId,
            receipt.logs
          );
          if (!timelockAddress) {
            throw new Error(`Could not find timelock address for operation id ${operationId}`);
          }

          proposalStages.push(
            new L1TimelockExecutionSingleStage(
              timelockAddress,
              scheduleBatchData.target,
              scheduleBatchData.value,
              scheduleBatchData.callData,
              scheduleBatchData.predecessor,
              scheduleBatchData.salt,
              l1SignerOrProvider
            )
          );
        }
      }
    }

    return proposalStages;
  }

  public async execute(): Promise<void> {
    const timelock = L1ArbitrumTimelock__factory.connect(
      this.timelockAddress,
      this.l1SignerOrProvider
    );

    const l1Value = (await this.getExecutionValue(this.target, this.data)) || this.value;
    await (
      await timelock.functions.execute(
        this.target,
        this.value,
        this.data,
        this.predecessor,
        this.salt,
        { value: l1Value }
      )
    ).wait();
  }
}

/**
 * When an l1 timelock period has passed, execute the batch proposal action
 */
export class L1TimelockExecutionBatchStage
  extends L1TimelockExecutionStage
  implements ProposalStage
{
  public constructor(
    timelockAddress: string,
    public readonly targets: string[],
    public readonly values: BigNumber[],
    public readonly datas: string[],
    public readonly predecessor: string,
    public readonly salt: string,
    l1SignerOrProvider: Signer | Provider
  ) {
    super(
      "L1TimelockExecutionBatchStage",
      timelockAddress,
      l1SignerOrProvider,
      keccak256(
        defaultAbiCoder.encode(
          ["address[]", "uint256[]", "bytes[]", "bytes32", "bytes32"],
          [targets, values, datas, predecessor, salt]
        )
      )
    );
  }

  public static async extractStages(
    receipt: TransactionReceipt,
    l1SignerOrProvider: Signer | Provider
  ): Promise<L1TimelockExecutionBatchStage[]> {
    const timelockInterface = ArbitrumTimelock__factory.createInterface();
    const bridgeInterface = Bridge__factory.createInterface();
    const proposalStages: L1TimelockExecutionBatchStage[] = [];

    for (const log of receipt.logs) {
      if (log.topics.find((t) => t === bridgeInterface.getEventTopic("BridgeCallTriggered"))) {
        const bridgeCallTriggered = bridgeInterface.parseLog(log)
          .args as unknown as BridgeCallTriggeredEventObject;
        const funcSig = bridgeCallTriggered.data.slice(0, 10);
        const schedBatchFunc =
          timelockInterface.functions[
            "scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)"
          ];
        if (funcSig === timelockInterface.getSighash(schedBatchFunc)) {
          // find all the schedule batch events
          const scheduleBatchData = L2TimelockExecutionBatchStage.decodeScheduleBatch(
            bridgeCallTriggered.data
          );
          const operationId = L2TimelockExecutionBatchStage.hashOperationBatch(
            scheduleBatchData.targets,
            scheduleBatchData.values,
            scheduleBatchData.callDatas,
            scheduleBatchData.predecessor,
            scheduleBatchData.salt
          );
          const timelockAddress = L2TimelockExecutionBatchStage.findTimelockAddress(
            operationId,
            receipt.logs
          );
          if (!timelockAddress) {
            throw new Error(`Could not find timelock address for operation id ${operationId}`);
          }
          proposalStages.push(
            new L1TimelockExecutionBatchStage(
              timelockAddress,
              scheduleBatchData.targets,
              scheduleBatchData.values,
              scheduleBatchData.callDatas,
              scheduleBatchData.predecessor,
              scheduleBatchData.salt,
              l1SignerOrProvider
            )
          );
        }
      }
    }

    return proposalStages;
  }

  public async execute(): Promise<void> {
    const timelock = L1ArbitrumTimelock__factory.connect(
      this.timelockAddress,
      this.l1SignerOrProvider
    );

    const values = [];
    for (let index = 0; index < this.targets.length; index++) {
      values[index] =
        (await this.getExecutionValue(this.targets[index], this.datas[index])) ||
        this.values[index];
    }

    await (
      await timelock.functions.executeBatch(
        this.targets,
        this.values,
        this.datas,
        this.predecessor,
        this.salt,
        { value: values.reduce((a, b) => a.add(b), BigNumber.from(0)) }
      )
    ).wait();
  }
}

/**
 * When a retryable ticket has been created, manually execute it
 */
export class RetryableExecutionStage implements ProposalStage {
  public readonly identifier: string;
  public name: string = "RetryableExecutionStage";

  constructor(public readonly l1ToL2Message: L1ToL2MessageReader | L1ToL2MessageWriter) {
    this.identifier = l1ToL2Message.retryableCreationId;
  }

  public static async extractStages(
    receipt: TransactionReceipt,
    l2ProviderOrSigner: Provider | Signer
  ): Promise<RetryableExecutionStage[]> {
    const stages: RetryableExecutionStage[] = [];
    const l1Receipt = new L1TransactionReceipt(receipt);
    const l1ToL2Events = l1Receipt.getMessageEvents();
    let network;
    for (const e of l1ToL2Events.filter(
      (e) => e.bridgeMessageEvent.kind === InboxMessageKind.L1MessageType_submitRetryableTx
    )) {
      if (!network) {
        network = await getL2Network(l2ProviderOrSigner);
      }
      if (e.bridgeMessageEvent.inbox.toLowerCase() !== network.ethBridge.inbox.toLowerCase()) {
        continue;
      }
      const messageParser = new SubmitRetryableMessageDataParser();
      const inboxMessageData = messageParser.parse(e.inboxMessageEvent.data);
      const message = L1ToL2Message.fromEventComponents(
        l2ProviderOrSigner,
        network.chainID,
        e.bridgeMessageEvent.sender,
        e.inboxMessageEvent.messageNum,
        e.bridgeMessageEvent.baseFeeL1,
        inboxMessageData
      );

      stages.push(new RetryableExecutionStage(message));
    }

    return stages;
  }

  public async status(): Promise<ProposalStageStatus> {
    const msgStatus = await this.l1ToL2Message.status();

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

  private isWriter(
    message: L1ToL2MessageReader | L1ToL2MessageWriter
  ): message is L1ToL2MessageWriter {
    return (message as L1ToL2MessageWriter).redeem != undefined;
  }

  public async execute(): Promise<void> {
    if (!this.isWriter(this.l1ToL2Message)) {
      throw new Error("Message is not a writer");
    }
    await (await this.l1ToL2Message.redeem()).wait();
  }

  public async getExecuteReceipt(): Promise<TransactionReceipt> {
    const redeemResult = await this.l1ToL2Message.getSuccessfulRedeem();

    if (redeemResult.status !== L1ToL2MessageStatus.REDEEMED) {
      throw new ProposalStageError(
        `Unexpected redeem result: ${redeemResult}`,
        this.identifier,
        this.name
      );
    }

    return redeemResult.l2TxReceipt;
  }

  public async getExecutionUrl(): Promise<string | undefined> {
    const execReceipt = await this.getExecuteReceipt();
    if (this.l1ToL2Message.chainId === 42161) {
      return `https://arbiscan.io/tx/${execReceipt.transactionHash}`;
    } else if (this.l1ToL2Message.chainId === 42170) {
      return `https://nova.arbiscan.io/tx/${execReceipt.transactionHash}`;
    } else {
      return undefined;
    }
  }
}
