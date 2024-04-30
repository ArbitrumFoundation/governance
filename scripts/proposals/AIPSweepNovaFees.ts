import { JsonRpcProvider } from "@ethersproject/providers";
import {
  L1ArbitrumTimelock__factory,
  IInbox__factory,
  ArbSys__factory,
} from "../../typechain-types";
import { Address } from "@arbitrum/sdk";
import { BigNumber, constants } from "ethers";
import { keccak256 } from "ethers/lib/utils";

const NOVA_FUNDS_SWEEP_SALT = keccak256("NOVA_FUNDS_SWEEP_SALT");

/**
 * Ad-hoc script for sweeping funds remaining in the Nova timelock alias to the fee router, as mentioned here: https://forum.arbitrum.foundation/t/aip-nova-fee-router-proposal/23310
 * Requires that the Nova Fee Router proposal already have executed.
 * Note that unsafeCreateRetryableTicket must be used because createRetryableTicket requires that L2CallValue be provided in the msg.value.
 * valueForMaxSubmissionCostWei must be set at proposal submission time, so needs to be sufficient to cover the retryable submission cost
 * at time of execution (i.e., a fairly high value should be used to be safe).
 * The L1 Timelock should be funded with at least valueForMaxSubmissionCostWei be the time of execution.
 */
const main = async (
  l1RpcUrl: string,
  targetChainRPCUrl: string,
  l1TimelockAddr: string, // mainnet: 0xE6841D92B0C345144506576eC13ECf5103aC7f49
  targetChainInboxAddr: string, // mainnet: 0xc4448b71118c9071Bcb9734A0EAc55D18A153949
  sweepDestinationAddr: string, // mainnet: 0x47a85c0a118127f3968a6a1a61e2a326517540d4 (nova to l1 fee router)
  refundAddressOnTargetChain: string,
  valueForMaxSubmissionCostWei: BigNumber
) => {
  const l1Provider = new JsonRpcProvider(l1RpcUrl);
  const targetChainProvider = new JsonRpcProvider(targetChainRPCUrl);

  //  encode inbox call:
  const inbox = IInbox__factory.connect(targetChainInboxAddr, l1Provider);
  const timelockL2Alias = new Address(l1TimelockAddr).applyAlias().value;
  //  send the full balance:
  // NOTE  is there any way the value here could decrease, since this is the timelock alias
  // (e.g., funds in this address get used for a governance action retryable execution?)
  // Should we leave some buffer just in case?
  // Or perhaps better: simply ensure there ends up being at  timelockL2AliasBalance ETH by manually topping it off
  // before execution if necessary.
  const timelockL2AliasBalance = await targetChainProvider.getBalance(timelockL2Alias);

  const inboxUnsafeCreateRetryableTicketCallDAta = inbox.interface.encodeFunctionData(
    "unsafeCreateRetryableTicket",
    [
      sweepDestinationAddr, // to
      timelockL2AliasBalance, // l2CallValue
      valueForMaxSubmissionCostWei, // maxSubmissionCost
      refundAddressOnTargetChain, // excessFeeRefundAddress
      refundAddressOnTargetChain, // callValueRefundAddress
      100, // gas limit, value doesn't matter (I think maybe it shouldn't be zero?)
      0, // maxFeePerGas: 0 for simplicity, retreyable will have to be explictly redeemed,
      "", // data
    ]
  );
  const l1Timelock = L1ArbitrumTimelock__factory.connect(l1TimelockAddr, l1Provider);
  const minDelay = await l1Timelock.getMinDelay();

  const l1TimelockScheduleCalldata = l1Timelock.interface.encodeFunctionData("schedule", [
    inbox.address,
    valueForMaxSubmissionCostWei,
    inboxUnsafeCreateRetryableTicketCallDAta,
    constants.HashZero,
    NOVA_FUNDS_SWEEP_SALT,
    minDelay,
  ]);

  const iArbSys = ArbSys__factory.createInterface();
  return iArbSys.encodeFunctionData("sendTxToL1", [l1TimelockAddr, l1TimelockScheduleCalldata]);
};
