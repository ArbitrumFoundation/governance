#!/bin/bash

yarn gen:proposalData --govChainProviderRPC https://arb1.arbitrum.io/rpc \
    --actionChainIds 42161 42161 \
    --actionAddresses 0x36D0170D92F66e8949eB276C3AC4FEA64f83704d 0x849E360a247132F961c9CBE95Ba39106c72e1268 \
    --writeToJsonPath ./scripts/proposals/AtlasFeesAIP/atlas-aip-data.json \
    --nonEmergencySCproposal true