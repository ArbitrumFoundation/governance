#!/bin/bash

# CoreGovTimelockUpdateDelayEightDayAction 0x31ab4d23D1D581b61f9D3CE70594BDD2156ea92C

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionChainIds 42161 \
    --actionAddresses 0x31ab4d23D1D581b61f9D3CE70594BDD2156ea92C \
    --writeToJsonPath ./scripts/proposals/CoreGovTimelockUpdateDelayEightDay/CoreGovTimelockUpdateDelayEightDay.json