#!/usr/bin/env bash
set -euo pipefail

# The fork gate must fail before the fork.
if results=$(forge test --match-path 'test/gov-actions/glamsterdam/ForkGateAction.t.sol' --evm-version osaka --json); then
    printf '%s\n' "$results"
    echo 'Expected the fork gate test to fail under Osaka.' >&2
    exit 1
fi

# Only the real probe test should fail, with ForkNotActive().
if ! jq -es '
    .[0]["test/gov-actions/glamsterdam/ForkGateAction.t.sol:ForkGateActionTest"].test_results
    | .["test_gatePassesAfterFork()"] as $gate
    | $gate.status == "Failure"
      and $gate.reason == "ForkNotActive()"
      and (del(.["test_gatePassesAfterFork()"]) | all(.status == "Success"))
' <<< "$results"; then
    printf '%s\n' "$results"
    echo 'Expected only test_gatePassesAfterFork() to fail with ForkNotActive().' >&2
    exit 1
fi
