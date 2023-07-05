# Submit a Proposal Example: AIP-1.2

Here, we'll go through an example of how an $ARB delegate can permissionlessly submit a DAO proposal using the Tally web app. We'll use [AIP-1.2](https://forum.arbitrum.foundation/t/proposal-aip-1-2-foundation-and-dao-governance/13362) and [AIP-1.1](https://forum.arbitrum.foundation/t/proposal-aip-1-1-lockup-budget-transparency/13360) as our examples.

To start, review the 7 general steps to submit a proposal using Tally in the Arbitrum Foundation docs [here](https://docs.arbitrum.foundation/how-tos/create-submit-dao-proposal#step-2-submit-your-on-chain-proposal-using-tally).


## Submitting AIP-1.2
For our example of AIP-1.2, do the following in particular:
- **Governor Selection (step 4):** 
    - Select the "Arbitrum Core" governor. 
        - _Explanation: AIP-1.2 updates the DAO Constitution Hash and sets the proposal thresholds for both governors to new values; both these these are constitutional actions, so the Core Governor must be used._ 
- **Proposal Title / Description (step 5):** 
    - Give the proposal a title and description; the title and description should be the same as the title and description in the corresponding [snapshot post](https://snapshot.org/#/arbitrumfoundation.eth/proposal/0x373dfa89fc9c5ccba8ed83fa3fa4f233edd270075b5f8f4f3902b408318d9d17), with any info about steps prior to proposal submission removed. You can use the description the [proposal JSON data here](../scripts/proposals/AIP12/data/42161-AIP1.2-data.json).
- **Proposal Action (step 6)**: 
    1. Select `Custom Action`
    1. In the `Enter the Target Address` Field" use `0x0000000000000000000000000000000000000064` (the ArbSys precompile).
    1. In the `Contract method` dropdown, select `sendTxToL1`.
    1. For the `destination` address field, use the [l1ArbitrumTimelock](https://etherscan.io/address/0xE6841D92B0C345144506576eC13ECf5103aC7f49#readProxyContract) address (`0xE6841D92B0C345144506576eC13ECf5103aC7f49`) as provided in the [proposal JSON data](../scripts/proposals/AIP12/data/42161-AIP1.2-data.json).
         - _Explanation: all executable core governor proposals will use the previous 4 steps; since constitutional proposals require a "round trip" before effectuating, their first step is to use ArbSys to encode an L2 to L1 message to the L1 timelock; for more, see ["Proposal Lifecycle Example"](./proposal_lifecycle_example.md)._ 
    1. For the `data` bytes field, use the `calldata` bytes in the [proposal JSON data](../scripts/proposals/AIP12/data/42161-AIP1.2-data.json). See below for instructions on regenerating / verifying the calldata locally.
        - _Explanation: all defining details of a particular core governor proposal are encoding in this calldata, i.e., the [governance action contract address](https://arbiscan.io/address/0x6274106eedD4848371D2C09e0352d67B795ED516) as well as the appropriate inbox/upgrade executor addresses such that the proposal targets the appropriate chain (in this case, Arbitrum One). We use scripts to generate a proposal's calldata_
    1. For the `ETH`/ `value` field, use `0`.
        - _Explanation: The Governor allows proposals to include callvalue, tho the vast majority of proposals won't require any_.

## Generating AIP-1.2 Calldata Locally 
Note that the data is already generated and committed to the git repo; run these steps to regeneate / confirm it.
1. git clone this repo
1. run `yarn install` and `yarn build`
1. Set the following environment variables:
    - `ARB_URL`: An RPC endpoint for Arbitrum One, e.g. "https://arb1.arbitrum.io/rpc"
    - `ETH_URL`: An RPC endpoint for L1 Ethereun, e.g., "https://mainnet.infura.io/v3/YOUR-KEY-HERE"
1. Run:  `yarn ts-node  ./scripts/proposals/AIP12/generateProposalData.ts`
Output will appear in logs and will be written to the [proposal JSON data](../scripts/proposals/AIP12/data/42161-AIP1.2-data.json) file.


## Submitting AIP-1.1
- **Governor Selection (step 4):** 
    - Select "Arbitrum Treasury" governor.
        - _Explanation: AIP-1.1 deals with the Arbitrum's Foundation budget management and relevant transparency; as per the constitution, this qualifies it as a "non-constitution" proposal — such propoposals use the Treasury governor._
- **Proposal Title / Description (step 5):** 
    - The on-chain proposal should have the same title and description as its corresponding [snapshot post](https://snapshot.org/#/arbitrumfoundation.eth/proposal/0x7203289844e807781e8d2ec110d4b97a79a29944cae06a52dbe315a16381a2ae).
- **Proposal Action (step 6)**: 
    1. Select `Custom Action`
    1. In the `Enter the Target Address` Field" use `0x9E43f733Da0445b35f038FB34a6Fb8C2947B984C`, a contract ("AIP1Point1Target") deployed for AIP-1.1 
    1. In the `Contract method` dropdown, select `effectuate`.
    1. For the `ETH`/ `value` field, use `0`.
        - _Explanation: AIP-1.1 technically doesn't require any on-chain execution. We use a designated contract anyway as a formality and for bookkeeping purposes_