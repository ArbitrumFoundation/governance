#!/bin/bash

# todo: replace with actual constitution hash once available
# todo: redeploy action contract with better estimate and replace address below

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionTypes \
        0 \
        1 \
    --actionChainIds \
        42161 \
        42161 \
    --actionAddresses \
        0x4a3126bfAaF7B657C591988963EB32d8bd398c04 \
        0x1D62fFeB72e4c360CcBbacf7c965153b00260417 \
    --upgradeValues \
        0 \
        0 \
    --upgradeDatas \
        "$(cast sig "perform()")" \
        "$(cast calldata "setConstitutionHash(bytes32)" 0x0000000000000000000000000000000000000000000000000000000000000000)" \
    --predecessor \
        0x0000000000000000000000000000000000000000000000000000000000000000 \
    --writeToJsonPath ./scripts/proposals/ActivateDvpQuorum/data.json