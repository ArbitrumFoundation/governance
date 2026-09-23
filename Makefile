# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
install                 :; yarn

FORK_GATE_TEST = test/gov-actions/glamsterdam/ForkGateAction.t.sol
FORK_GATE_SNAPSHOT = .gas-snapshot-fork-gate

# Build & test
build                   :; forge build
coverage                :
	forge coverage --no-match-path $(FORK_GATE_TEST)
	forge coverage --match-path $(FORK_GATE_TEST) --evm-version amsterdam
gas                     :
	forge test --gas-report --no-match-path $(FORK_GATE_TEST)
	forge test --gas-report --match-path $(FORK_GATE_TEST) --evm-version amsterdam
gas-check               :
	forge snapshot --check --tolerance 1 --no-match-path $(FORK_GATE_TEST)
	forge snapshot --check $(FORK_GATE_SNAPSHOT) --tolerance 1 --match-path $(FORK_GATE_TEST) --evm-version amsterdam
snapshot                :
	forge snapshot --no-match-path $(FORK_GATE_TEST)
	forge snapshot --snap $(FORK_GATE_SNAPSHOT) --match-path $(FORK_GATE_TEST) --evm-version amsterdam
test-unit               :
	forge test -vvv --no-match-path $(FORK_GATE_TEST)
	$(MAKE) test-fork-gate
test-fork-gate           :; forge test -vvv --match-path $(FORK_GATE_TEST) --evm-version amsterdam
test-fork-gate-osaka     :; bash test/gov-actions/glamsterdam/test-fork-gate-osaka.bash
clean                   :; forge clean
fmt                     :; forge fmt
gen-network             :; yarn gen:network
test                    :  test-unit
test-action-storage     :; ./scripts/test-action-storage.sh
sc-election-test		:; FOUNDRY_MATCH_PATH='test/security-council-mgmt/**/*.t.sol' make test
test-integration        :; yarn test:integration
