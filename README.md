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
yarn test:integration
```

## Governance deployer

Arbitrum governance consists of multiple L1, Arbitrum One and Nova contracts. Those contracts are interdependent and they require careful deployment and initialization flow. We have automated all the deployment steps in `governanceDeployer.ts` script. On a high level script does the following:
- deploy L1, Arb and Nova governance contracts
- initialize governance contracts 
- deploy and initialize Arbitrum token
- move tokens to all stakeholders according to predefined breakdown
- set up token distributor which enables token claiming to eligible Arbitrum users

There are additional scripts that do the verification of deployed governance, and preparation and verification of protocol ownership transfer to the Arbitrum DAO.  
  
In order to successfully deploy governance, various configuration parameters need to be prepared and set. Config parameters are grouped in these files:
- `deployConfig.json`
  - contains governance, token and token distribution parameters
  - list of all parameters can be found in `scripts/deployerConfig.ts`
- `vestingWalletRecipients.json`
  - key-value pairs in JSON format where key is account for which vested wallet is going to be created and value is amount of tokens entitled to the account
- `daoRecipients.json`
  - key-value pairs in JSON format where key is DAO account and value is amount of tokens entitled to the DAO
- `claimRecipients.json`
  - JSON file containing info about Arbitrum users eligible for Arb token claim
- `.env`, environment vars required to deploy governance:
  - boolean determining if governance is deployed to test or prod environment
  - L1, Arb, Nova RPCs
  - deployer keys
  - location of config files
  - location of `deployedContracts.json` which is used to output addresses of deployed contracts and deployment milestones
  - location of files where unsigned transactions for transfering protocol ownership will be stored
  - full list of variables can be found in `.env-sample`

Next section shows detailed guide how to deploy governance in the local test environment.


### Guide for deploying governance to local test environment

To deploy governance in local env we need to have L1 and Nitro instances up and running (same as in previous section). Start the test node by running following script in `nitro` repo:

```
./test-node.bash --init --no-blockscout
```

Now that Nitro is running, let's prepare Arbitrum One network. Run following script to deploy Arb token bridge contracts:

```
yarn gen:network
```

Info about all the protocol and token bridge contracts is written to `files/local/network.json`.

Do the same for Nova:

```
yarn run gen:nova:network
```
Token bridge contracts are deployed and info is written to `files/local/networkNova.json`.  

Next, we need to do preparation for governance deployment. First install the dependencies:

```
yarn install
```

One of the prerequisites is to have env vars properly set. When deploying to test node it's enough to simply copy the sample values:

```
cp .env-sample .env
```

There's also a set of governance config parameters that need to be properly set prior to deployment. These parameters are used to initialize Arb token, token distribution and different governance variables. They can be edited in following file:
```
cat files/local/deployConfig.json
```

Compile governance contracts:
```
yarn build
```

During the deployment process deployer will write addresses of deployed contracts to `deployedContracts.json`. The same file is also used by deployer to keep track of deployment milestones. If deployment script fails for any reason during the deployment, it can be re-executed and it will automatically continue from the step where it failed in the previous run. In case governance is being deployed from scratch (and there were previous deployments) make sure to remove `deployedContracts.json` file containing cached info and milestones:
```
rm files/local/deployedContracts.json
```

Now everything's ready to start the deployment process. Run the following script:
```
yarn deploy:governance
```

Script deploys and initializes governance contracts. Addresses of deployed contracts are stored in `files/local/deployedContract.json`. Once deployment is finished make sure everything is properly deployed:
```
yarn verify:governance
```

Next step is token allocation. Tokens need to be distributed to treasury, foundation, team, vested investor wallets, DAOs. This also includes deploying TokenDistributor and setting token claim recipients. Depending on the number of recipients this process could take up to few hours.
```
yarn allocate:tokens
```

Now we can check tokens were properly distributed to all the stakeholders as intended.
```
yarn verify:distribution:full
```

Optionally distribute tokens to daos
```
yarn allocate:dao:tokens
```

And verify they were distributed successfully
```
yarn verify:dao:distributions
```

There's another set of tasks required - once governance is deployed ownership of existing Arb/Nova protocol contracts shall be transferred to the DAO. Running the following script will prepare (unsigned) transactions that need to be executed to fully transfer the ownership:
```
yarn prepare:ownership:transfer
```

Script outputs 2 JSON files which contain unsigned TXs (`data` and `to` fields):
- `files/local/arbTransferAssetsTXs.json`
- `files/local/novaTransferAssetsTXs.json`

In production mode these TXs will be signed and executed by protocol owner multisig. In test mode however we can execute them directly by running script:
```
yarn execute:ownership:transfer
```

Finally, let's make sure owership of protocol assets has been succsessfully transferred to DAO. Verification script works for both production and testing mode.
```
yarn verify:ownership:transfer
```




