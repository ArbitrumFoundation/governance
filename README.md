# Arbitrum Governance
This project contains smart contracts for Arbitrum token and governance. Please see the following for a more detailed explanation:
* [Overview](./docs/overview.md)
* [Proposal lifecycle](./docs/proposal_lifecycle_example.md)

## Run Foundry unit tests

If not already installed, install [Foundry](https://github.com/foundry-rs/foundry#installation).

Make sure Foundry is up-to-date
```
foundryup
```

Install dependencies
```
make install
```

Build project
```
make build
```

Run test cases
```
make test
```

## Run Hardhat integration tests

Running integration tests requires local setup for L1 client and the Nitro sequencer. We will use prepared installation script.   

Start by cloning Nitro repo
```
git clone git@github.com:OffchainLabs/nitro.git
```

Checkout master branch and init submodules
``` 
git checkout master
git pull origin master
git submodule update --init
```

Run the script which will build and start Nitro nodes in Docker containers
```
./test-node.bash --init --no-blockscout
```

Make sure all containers are up and running
```
❯ docker ps
CONTAINER ID   IMAGE                       COMMAND                  CREATED             STATUS             PORTS                                                                       NAMES
83c506bb32a6   nitro-poster                "/usr/local/bin/nitr…"   About an hour ago   Up About an hour   127.0.0.1:8147->8547/tcp, 127.0.0.1:8148->8548/tcp                          nitro-poster-1
ef279f896c24   nitro-staker-unsafe         "/usr/local/bin/nitr…"   About an hour ago   Up About an hour   127.0.0.1:8047->8547/tcp, 127.0.0.1:8048->8548/tcp                          nitro-staker-unsafe-1
fe0df15edae5   nitro-sequencer             "/usr/local/bin/nitr…"   About an hour ago   Up About an hour   127.0.0.1:8547-8548->8547-8548/tcp, 127.0.0.1:9642->9642/tcp                nitro-sequencer-1
5c72ab0f5f54   redis:6.2.6                 "docker-entrypoint.s…"   About an hour ago   Up About an hour   127.0.0.1:6379->6379/tcp                                                    nitro-redis-1
aceb02d8a616   ethereum/client-go:stable   "geth --keystore /ke…"   About an hour ago   Up About an hour   127.0.0.1:8545-8546->8545-8546/tcp, 127.0.0.1:30303->30303/tcp, 30303/udp   nitro-geth-1
```

Set the env variables (you can use the ones from .env-sample)
```
cp .env-sample .env
```

Install dependencies
```
yarn
```

Compile contracts
```
yarn build
```

Deploy Nitro contracts to the local node
```
yarn gen:network
```

Addresses for deployed contracts are stored to `localNetwork.json`

Finally run integration tests against local node
```
yarn test-integration
```

