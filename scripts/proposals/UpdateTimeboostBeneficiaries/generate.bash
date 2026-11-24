#!/bin/bash

ARB1_ELA=0x5fcb496a31b7AE91e7c9078Ec662bd7A55cd3079
NOVA_ELA=0xa5aBADAF73DFcf5261C7f55420418736707Dc0db

ARB1_BENEFICIARY=0xa4a8a4e2fe847af59d340926adcdef6e988bb1f1
NOVA_BENEFICIARY=0xeDF94c9C8873B6942800B31af7773a22969Ab93e

yarn gen:proposalData \
    --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionTypes \
        1 \
        1 \
    --actionChainIds \
        42161 \
        42170 \
    --actionAddresses \
        $ARB1_ELA \
        $NOVA_ELA \
    --upgradeValues \
        0 \
        0 \
    --upgradeDatas \
        "$(cast calldata "setBeneficiary(address)" $ARB1_BENEFICIARY)" \
        "$(cast calldata "setBeneficiary(address)" $NOVA_BENEFICIARY)" \
    --predecessor \
        0x0000000000000000000000000000000000000000000000000000000000000000 \
    --writeToJsonPath ./scripts/proposals/UpdateTimeboostBeneficiaries/data.json