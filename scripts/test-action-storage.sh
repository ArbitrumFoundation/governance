#!/bin/bash

# compile contracts so out/ directory is populated
forge build

CONTRACTS=$(find out/ -name "*Action.json" | sed 's/\.json$//' | awk -F/ '{print $NF}')

EXIT_CODE=0

for CONTRACT in $CONTRACTS; do
    IS_NO_STORAGE=$(forge inspect $CONTRACT storage | jq '.storage == []')
    if [ "$IS_NO_STORAGE" = "false" ]; then
        echo "$CONTRACT has storage"
        EXIT_CODE=1
    fi
done;

if [ $EXIT_CODE -eq 0 ]; then
    echo "All action contracts have no storage"
fi

exit $EXIT_CODE
