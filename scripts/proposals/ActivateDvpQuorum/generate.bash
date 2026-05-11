#!/bin/bash

# todo: redeploy action contract with better estimate and replace address below

# constitution hash comes from: https://github.com/ArbitrumFoundation/docs/pull/1164/changes/001d57cfc17a2fd6c7f23a01ff99c351480c3e69

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionTypes \
        0 \
        1 \
    --actionChainIds \
        42161 \
        42161 \
    --actionAddresses \
        0xbeA14C43EE8324B764D699B4E1B5dD9d1f1825c9 \
        0x1D62fFeB72e4c360CcBbacf7c965153b00260417 \
    --upgradeValues \
        0 \
        0 \
    --upgradeDatas \
        "$(cast sig "perform()")" \
        "$(cast calldata "setConstitutionHash(bytes32)" 0x263080bed3962d0476fa84fbb32ab81dfff1244e2b145f9864da24353b2f3b05)" \
    --predecessor \
        0x0000000000000000000000000000000000000000000000000000000000000000 \
    --writeToJsonPath ./scripts/proposals/ActivateDvpQuorum/data.json