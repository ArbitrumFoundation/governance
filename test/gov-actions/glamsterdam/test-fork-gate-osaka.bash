#!/usr/bin/env bash
set -euo pipefail

if results=$(forge test --match-path 'test/gov-actions/glamsterdam/ForkGateAction.t.sol' --evm-version osaka --json); then
    printf '%s\n' "$results"
    echo 'Expected the fork gate test to fail under Osaka.' >&2
    exit 1
fi

if ! printf '%s\n' "$results" | jq -e '
    .["test/gov-actions/glamsterdam/ForkGateAction.t.sol:ForkGateActionTest"].test_results
    | .["test_gatePassesAfterFork()"].status == "Failure"
      and .["test_gatePassesAfterFork()"].reason == "ForkNotActive()"
      and (to_entries | all(.key == "test_gatePassesAfterFork()" or .value.status == "Success"))
'; then
    printf '%s\n' "$results"
    echo 'Expected only test_gatePassesAfterFork() to fail with ForkNotActive().' >&2
    exit 1
fi
