# Submit a Core Proposal Via Tally

Before a proposal can be submitted, its action contrats must be deployed, its JSON data must be prepared, and the it must  pass the simulation tests. See [here](./creating-a-proposal.md) for details on those steps. 

Proposals can be submitted via any means of accessing the DAO governance smart contracts; the Tally UI is recommended. 


## Submitting A Core Proposal
- **Start create proposal** Navigate to https://www.tally.xyz/gov/arbitrum and click "Create new proposal".
- **Governor Selection** 
    - Select the "Arbitrum Core" governor. 
- **Proposal Title / Description** 
    - Give the proposal a title and description; the title and description may be similar to the title and description in the corresponding snapshot post, tho adding additional info to the description at this stage may be appropriate. 
- **Proposal Action**: 
    1. Select`Add Action` and then `Custom Action`
    1. In the `Enter the Target Address` Field" use `0x0000000000000000000000000000000000000064` (the ArbSys precompile).
    1. In the `Contract method` dropdown, select `sendTxToL1`.
    1. For the `destination` address field, use the [l1ArbitrumTimelock](https://etherscan.io/address/0xE6841D92B0C345144506576eC13ECf5103aC7f49#readProxyContract) address (`0xE6841D92B0C345144506576eC13ECf5103aC7f49`) as provided in the proposal JSON data.
    1. For the `data` bytes field, use the `calldata` bytes in the proposal JSON data. 
    1. Unless the proposal requires value to send (which is unusual) set 0 in the `value` field.
- **Publishing**    
    - Double check all values. When ready, select "publish" or "save draft" to send to a delegate to publish; note that a mimimum of 1,000,000 voting power is required to publish a proposal. 
    

You can also review the 7 general steps to submit a proposal using Tally in the Arbitrum Foundation docs [here](https://docs.arbitrum.foundation/how-tos/create-submit-dao-proposal#step-2-submit-your-on-chain-proposal-using-tally).