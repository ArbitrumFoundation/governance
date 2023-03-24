import { getL1Network, getL2Network } from "@arbitrum/sdk";
import { ArbSys__factory } from "@arbitrum/sdk/dist/lib/abi/factories/ArbSys__factory";
import { ARB_SYS_ADDRESS } from "@arbitrum/sdk/dist/lib/dataEntities/constants";
import { defaultAbiCoder } from "@ethersproject/abi";
import { JsonRpcProvider } from "@ethersproject/providers";
import { BigNumber, constants, utils } from "ethers";
import { id, keccak256 } from "ethers/lib/utils";
import {
  L1ArbitrumTimelock__factory,
  L2ArbitrumGovernor__factory,
  ArbitrumTimelock__factory,
  UpgradeExecutor__factory,
} from "../typechain-types";

/**
 * Config network where the governor is located.
 */
export interface L2GovConfig {
  /**
   * Address of the governor where the proposal will be sent
   */
  readonly governorAddr: string;
  /**
   * Provider for the network where the governor is located
   */
  readonly provider: JsonRpcProvider;
}

/**
 * Config for the L1 network on which this l2 networks are based
 */
export interface L1GovConfig {
  /**
   * The address of the timelock on L1
   */
  readonly timelockAddr: string;
  /**
   * Provider for the L1 network
   */
  readonly provider: JsonRpcProvider;
}

/**
 * Config for the network where the upgrade will actually take place - could be ArbOne, L1, or ArbNova.
 */
export interface UpgradeConfig {
  /**
   * Address of the upgrade executor that will execute the upgrade
   */
  readonly upgradeExecutorAddr: string;
  /**
   * Provider for the network where the upgrade will take place
   */
  readonly provider: JsonRpcProvider;
}

export interface UpgradePathConfig {}

/**
 * A governance proposal
 */
export class Proposal {
  public constructor(
    public readonly target: string,
    public readonly value: BigNumber,
    public readonly callData: string,
    public readonly description: string
  ) {}

  /**
   * Form a proposal from the call data sent to the propose method
   * @param data
   * @returns
   */
  public static fromData(data: string) {
    const arbGovInterface = L2ArbitrumGovernor__factory.createInterface();
    const parts = arbGovInterface.decodeFunctionData("propose", data) as [
      string[],
      BigNumber[],
      string[],
      string
    ];

    return new Proposal(parts[0][0], parts[1][0], parts[2][0], parts[3]);
  }

  /**
   * Encode the proposal parameters as call data to be sent to the governor
   */
  public encode() {
    const arbGovInterface = L2ArbitrumGovernor__factory.createInterface();
    return arbGovInterface.encodeFunctionData("propose", [
      [this.target],
      [this.value],
      [this.callData],
      this.description,
    ]);
  }

  /**
   * The id of this proposal
   */
  public id() {
    const descriptionHash = id(this.description);
    return keccak256(
      defaultAbiCoder.encode(
        ["address[]", "uint256[]", "bytes[]", "bytes32"],
        [[this.target], [this.value], [this.callData], descriptionHash]
      )
    );
  }
}

/**
 * Creates proposals that originate on an L2, are then withdrawn to an L1 and go through a timelock
 * there, and are then finally executed on another L2 or L1.
 */
export class RoundTripProposalCreator {
  /**
   * A proposal creator for a specific round trip config
   * @param l1Config Config for the L1 network on which this l2 networks are based
   * @param targetNetworkConfig Config for the network where the upgrade will actually take place - could be ArbOne, L1, or ArbNova.
   */
  constructor(
    public readonly l1Config: L1GovConfig,
    public readonly targetNetworkConfig: UpgradeConfig
  ) {}

  /**
   * Create a a new proposal
   * @param upgradeAddr The address of the upgrade contract that will be called by an UpgradeExecutor
   * @param upgradeValue Value sent to the upgrade contract
   * @param upgradeData Call data sent to the upgrade contract
   * @param proposalDescription The proposal description
   * @returns
   */
  public async create(
    upgradeAddr: string,
    upgradeValue: BigNumber,
    upgradeData: string,
    proposalDescription: string
  ): Promise<Proposal> {
    const descriptionHash = id(proposalDescription);

    // the upgrade executor
    const iUpgradeExecutor = UpgradeExecutor__factory.createInterface();
    const upgradeExecutorCallData = iUpgradeExecutor.encodeFunctionData(
      "execute",
      [upgradeAddr, upgradeData]
    );
    const upgradeExecutorTo = this.targetNetworkConfig.upgradeExecutorAddr;
    const upgradeExecutorValue = upgradeValue;

    // the l1 timelock
    const l1TimelockTo = this.l1Config.timelockAddr;
    const l1Timelock = L1ArbitrumTimelock__factory.connect(
      l1TimelockTo,
      this.l1Config.provider
    );
    const minDelay = await l1Timelock.getMinDelay();

    const inbox = await (async () => {
      this.targetNetworkConfig.provider;
      try {
        const l2Network = await getL2Network(this.targetNetworkConfig.provider);
        return l2Network.ethBridge.inbox;
      } catch (err) {
        // just check this is an expected l1 chain id and throw if not
        await getL1Network(this.targetNetworkConfig.provider);
        return null;
      }
    })();

    let l1To: string, l1Data: string, l1Value: BigNumber;
    if (inbox) {
      l1To = await l1Timelock.RETRYABLE_TICKET_MAGIC();
      l1Data = defaultAbiCoder.encode(
        ["address", "address", "uint256", "uint256", "uint256", "bytes"],
        [
          inbox,
          upgradeExecutorTo,
          upgradeExecutorValue,
          0,
          0,
          upgradeExecutorCallData,
        ]
      );
      // this value gets ignored from xchain upgrades
      l1Value = BigNumber.from(0);
    } else {
      l1To = upgradeExecutorTo;
      l1Data = upgradeExecutorCallData;
      l1Value = upgradeExecutorValue;
    }

    const l1TImelockScheduleCallData = l1Timelock.interface.encodeFunctionData(
      "schedule",
      [l1To, l1Value, l1Data, constants.HashZero, descriptionHash, minDelay]
    );

    const iArbSys = ArbSys__factory.createInterface();
    const proposalCallData = iArbSys.encodeFunctionData("sendTxToL1", [
      l1TimelockTo,
      l1TImelockScheduleCallData,
    ]);

    return new Proposal(
      ARB_SYS_ADDRESS,
      BigNumber.from(0),
      proposalCallData,
      proposalDescription
    );
  }

  public async createTimelockScheduleArgs(
    l2GovConfig: L2GovConfig,
    upgradeAddr: string,
    description: string,
    options?: {
      _upgradeValue?: BigNumber,
      _upgradeArgs?: string,
      _delay?: BigNumber,
      _predecessor?: string,
    }
  
  )  {
    const upgradeValue = options?._upgradeValue || BigNumber.from(0) // default to 0 value
    const predecessor = options?._predecessor || "0x"; // default to no predecessor
    
    const l2Gov = await L2ArbitrumGovernor__factory.connect(  l2GovConfig.governorAddr, l2GovConfig.provider)
    const l2TimelockAddress = await l2Gov.timelock()
    const l2Timelock = await ArbitrumTimelock__factory.connect(l2TimelockAddress, l2GovConfig.provider)
    const delay = options?._delay? options?._delay : await l2Timelock.getMinDelay(); // default to min delay

    let ABI = [ "function perform() external" ]; // TODO: allow for optional args
    let iface = new utils.Interface(ABI);
    const upgradeData =  iface.encodeFunctionData("perform")

    const proposalCallData = ( await this.create(upgradeAddr, upgradeValue, upgradeData, description)).callData
    const salt = keccak256(  defaultAbiCoder.encode( ["string"], [description]))
    return {
      target: ARB_SYS_ADDRESS,
      value: upgradeValue.toNumber(),
      data: proposalCallData,
      predecessor,
      salt,
      delay: delay.toNumber()
    }

  }
}
