#!/bin/bash

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionChainIds \
        42161 \
    --actionAddresses \
        0x4a3126bfAaF7B657C591988963EB32d8bd398c04 \
    --writeToJsonPath ./scripts/proposals/ActivateDvpQuorum/data.json