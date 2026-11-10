#!/bin/bash

yarn gen:proposalData --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionChainIds \
        1 \
    --actionAddresses \
        0x7F089c0daF0181F7aFD533f5f3265301bB09d562 \
    --upgradeDatas \
        $(cast calldata "perform(address[],address[],uint256,uint256,uint256)" "[0xdC035D45d973E3EC169d2276DDab16f1e407384F,0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD]" "[0x84b9700e28b23f873b82c1beb23d86c091b6079e,0x84b9700e28b23f873b82c1beb23d86c091b6079e]" 0 0 $(cast to-wei 0.0005)) \
    --upgradeValues \
        $(cast to-wei 0.0005) \
    --predecessor \
        0x0000000000000000000000000000000000000000000000000000000000000000 \
    --writeToJsonPath \
        ./scripts/proposals/usds-gateway-register/data.json