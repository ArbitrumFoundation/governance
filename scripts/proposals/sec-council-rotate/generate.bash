#!/bin/bash

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionChainIds 42161 \
    --actionAddresses \
        0x86E93E21AD108CaE7ADe482C34C230Bfd94D4A8B \
    --writeToJsonPath ./scripts/proposals/sec-council-rotate/data.json