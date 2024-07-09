#!/bin/bash

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionChainIds 42170 \
    --actionAddresses 0x382165c3A07F006b9Bf3173C08ECcE8bb68462E4 \
    --writeToJsonPath ./scripts/proposals/NovaFeeRoutingAIP/NovaFeeRoutingAIP.json