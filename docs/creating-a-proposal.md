# Creating a core proposal 

The following is a guide to creating an on-chain Arbitrum DAO core governor proposal. 

Prior to creating a proposal, it should be publically discussed on the Arbitrum Forum and a an off-chian temperature-check snapshot poll should be conducted; see [Arbitrum DAO docs](https://docs.arbitrum.foundation/how-tos/create-submit-dao-proposal#step-2-submit-your-on-chain-proposal-using-tally) for details. 

Once a temperature check has passed, the following things can be done:

1. **Create Action Contract(s)**: Create the Governance Action Contract(s) for the proposal. See [here](../src/gov-action-contracts/README.md) for a guide to Governance Action Contracts.

1. **(Optional) Unit Tests**: Write unit tests for the Action Contracts if appropriate, i.e., if they introduce non-trivial new logic. 

1. **Deploy And Verify Action Contracts**: Using `forge create`, deploy Action Contracts on their appropriate chain(s) (Ethereum, Arbitrum One, or Nova) and verify their bytecode on etherscan/arbiscan. (Note that no additional scripting should be used/required for Action Contract deployment.)   

1. **Generate Propoposal Calldata**:
    a. Create a new directory under ./scripts/proposals/ for your proposal data, e.g.

    ```
    mkdir ./scipts/proposals/AIPMyProp
    ```
    b. Generate proposal data using `yarn gen:proposalData` using the addresses of the deloyed action contracts, and providing a path to store the new JSON file.

    For example:
    ```
        yarn gen:proposalData \
        --govChainProviderRPC https://arb1.arbitrum.io/rpc \
        --actionChainIds 1 42161 \
        --actionAddresses 0xAddressA 0xAddressB   \
        --writeToJsonPath ./scipts/proposals/AIPMyProp/my-prop-data.json  
    ```
    Note that the indices for the chain ids correspond  with those of the action contracts. E.g., in the example, 0xAddressA should be deployed on chain 1 (Ethereum) and 0xAddressB should be deployed on chain 42161 (Arbitrum One.)

    Run `yarn gen:proposalData --help` to see all optional parameters.

    Once the data JSON is properly created, it can be included in a public pull request to this repo.

    Note that while some prior proposals include description text and/or deployment scripts, that is no longer necessary. 

1. **Run Simulation**

    Using the calldata generated in the previous step, test the proposal using [the Arbitrum DAO governance seatbelt](https://github.com/ArbitrumFoundation/governance-seatbelt). Include the configuration in a PR to the seatbelt repo ([example](https://github.com/ArbitrumFoundation/governance-seatbelt/pull/26)).

    The seatbelt will generate a human readable report of all of the state changes in the proposal; only proceed if the report's result are what is expected. 

1. **Submit Proposal In Tally UI** See [here](./submit_a_proposal.md). 



