#!/bin/bash

# CoreGovTimelockUpdateDelayEightDayAction 0x5B947D8bF197467be7ef381b7cAfEE0A7B35737A

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionChainIds 42161 \
    --actionAddresses 0x5B947D8bF197467be7ef381b7cAfEE0A7B35737A \
    --writeToJsonPath ./scripts/proposals/CoreGovTimelockUpdateDelayEightDay/CoreGovTimelockUpdateDelayEightDay.json