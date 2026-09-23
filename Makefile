# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
install                 :; yarn

FORK_GATE_TEST = test/gov-actions/glamsterdam/ForkGateAction.t.sol
FORK_GATE_OSAKA_CHECK = \
	.[0]["$(FORK_GATE_TEST):ForkGateActionTest"].test_results \
	| .["test_gatePassesAfterFork()"] as $$gate \
	| $$gate.status == "Failure" and $$gate.reason == "ForkNotActive()" \
	  and (to_entries | all(.key == "test_gatePassesAfterFork()" or .value.status == "Success"))

# Build & test
build                   :; forge build
coverage                :; forge coverage
gas                     :; forge test --gas-report
gas-check               :; forge snapshot --check --tolerance 1
snapshot                :; forge snapshot
test-unit               :; forge test -vvv
test-fork-gate-osaka     :
	! results=$$(forge test --match-path $(FORK_GATE_TEST) --evm-version osaka --json) && \
	printf '%s\n' "$$results" | jq -es '$(FORK_GATE_OSAKA_CHECK)'
clean                   :; forge clean
fmt                     :; forge fmt
gen-network             :; yarn gen:network
test                    :  test-unit
test-action-storage     :; ./scripts/test-action-storage.sh
sc-election-test		:; FOUNDRY_MATCH_PATH='test/security-council-mgmt/**/*.t.sol' make test
test-integration        :; yarn test:integration
