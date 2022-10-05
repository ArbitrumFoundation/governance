# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
install   :; forge install

# Build & test
build     :; forge build
coverage  :; forge coverage
gas       :; forge test --gas-report
gas-check :; forge snapshot --check
snapshot  :; forge snapshot
test-forge:; forge test -vvv
clean     :; forge clean
fmt       :; forge fmt
test      :  test-forge
