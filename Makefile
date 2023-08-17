# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
install					:; yarn

# Build & test
build					:; forge build
coverage				:; forge coverage
gas						:; forge test --gas-report
gas-check				:; forge snapshot --check
snapshot				:; forge snapshot
test-unit				:; forge test -vvv
clean					:; forge clean
fmt						:; forge fmt
gen-network				:; yarn gen:network
test					:  test-unit
test-integration		:; yarn test:integration
test-action-storage		:; ./scripts/test-action-storage.sh
