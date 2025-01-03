// generates a proposal payload to sweep the Nova L1 Timelock alias ETH balance to the fee router contract.

import { BigNumber, ethers } from 'ethers'
import {
  IInbox__factory,
  L1ArbitrumTimelock__factory,
} from '../../../typechain-types'
import { JsonRpcProvider } from '@ethersproject/providers'
import fs from 'fs'
;(async () => {
  const l1TimelockAlias = '0xf7951d92b0c345144506576ec13ecf5103ac905a'
  const novaInbox = '0xc4448b71118c9071Bcb9734A0EAc55D18A153949'
  const novaToParentRouter = '0x36D0170D92F66e8949eB276C3AC4FEA64f83704d'
  const maxL1GasPrice = ethers.utils.parseUnits('1000', 'gwei') // used to calculate maxSubmissionCost
  const aliasBalance = await new JsonRpcProvider(
    'https://nova.arbitrum.io/rpc'
  ).getBalance(l1TimelockAlias)

  const timelockIface = L1ArbitrumTimelock__factory.createInterface()
  const inboxIface = IInbox__factory.createInterface()

  const maxSubmissionCost = calcSubmissionCost(maxL1GasPrice)

  const unsafeCreateRetryableCalldata = inboxIface.encodeFunctionData(
    'unsafeCreateRetryableTicket',
    [
      novaToParentRouter, // to
      aliasBalance.sub(maxSubmissionCost), // l2CallValue
      maxSubmissionCost, // maxSubmissionCost
      novaToParentRouter, // excessFeeRefundAddress
      novaToParentRouter, // callValueRefundAddress
      0, // gasLimit
      0, // maxFeePerGas
      '0x', // calldata
    ]
  )
  const scheduleCalldata = timelockIface.encodeFunctionData('schedule', [
    novaInbox,
    0,
    unsafeCreateRetryableCalldata,
    '0x0000000000000000000000000000000000000000000000000000000000000000',
    '0xafa240dd4c6513a86965b2fdce079dc265548e8d301653ccf5602a9126c06bf8',
    259200,
  ])

  console.log(scheduleCalldata)

  fs.writeFileSync(
    './scripts/proposals/NovaFeeSweep/proposal.txt',
    scheduleCalldata
  )
})()

function calcSubmissionCost(baseFee: BigNumber) {
  // data length is zero
  // from the contract: return (1400 + 6 * dataLength) * (baseFee == 0 ? block.basefee : baseFee);
  return baseFee.mul(1400)
}
