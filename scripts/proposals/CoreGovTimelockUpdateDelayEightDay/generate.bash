#!/bin/bash

# CoreGovTimelockUpdateDelayEightDayAction 0x17D2448355D6F87F0391B1304A268db9057C72a8

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionChainIds 42161 \
    --actionAddresses 0x17D2448355D6F87F0391B1304A268db9057C72a8 \
    --writeToJsonPath ./scripts/proposals/CoreGovTimelockUpdateDelayEightDay/CoreGovTimelockUpdateDelayEightDay.json