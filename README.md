# Arbitrum Governance
This project contains smart contracts for Arbitrum token and governance. Please see the following for a more detailed explanation:
* [Overview](./docs/overview.md)
* [Proposal lifecycle](./docs/proposal_lifecycle_example.md)
* [Governance Action Contracts](./src/gov-action-contracts/README.md)
* [Security Council Elections](./docs/security-council-mgmt.md)
* [Security Audit](./audits/trail_of_bits_governance_report_1_6_2023.pdf)
* [Gotchas](./docs/gotchas.md)
* [Proposal Monitor](./docs/proposalMonitor.md)

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
cp files/local/.env-sample .env
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

## Generate Code Coverage Report

Install dependencies
```
brew install lcov
```

Generate Report
```
yarn coverage:report
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
yarn verify:dao:distribution
```

There's another set of tasks required - once governance is deployed ownership of existing Arb/Nova protocol contracts shall be transferred to the DAO. Running the following script will prepare (unsigned) transactions that need to be executed to fully transfer the ownership:
```
yarn prepare:ownership:transfer
```

Script outputs 6 JSON files which contain unsigned TXs in a format that can be inported to Gnosis Safe UI:
- `./files/local/l1ArbProtocolTransferTXs.json`
- `./files/local/l1ArbTokenBridgeTransferTXs.json`
- `./files/local/arbTransferAssetsTXs.json`
- `./files/local/l1NovaProtocolTransferTXs.json`
- `./files/local/l1NovaTokenBridgeTransferTXs.json`
- `./files/local/novaTransferAssetsTXs.json`

In production mode these TXs will be signed and executed by protocol owner multisig. In test mode however we can execute them directly by running script:
```
yarn execute:ownership:transfer
```

Finally, let's make sure owership of protocol assets has been succsessfully transferred to DAO. Verification script works for both production and testing mode.
```
yarn verify:ownership:transfer
```

### ArbitrumFoundationVestingWallet Deployer

#### Deploy
- Set `ARB_URL` and `ARB_KEY` env vars
- Set FoundationWalletDeploymentConfig variables (for target chain) in [config file](./scripts/foundation-wallet-deployment/config.ts)
- run ```yarn hardhat compile ```
- run ```yarn deploy:foundation-wallet ```

#### Verify Deployment
_Verify contract's bytecode on Arbiscan and verify that contract's parameters were set correctly_
- Set `ARB_URL` and `ARBISCAN_API_KEY` env vars 
- Set DeployedWallet address (for target chain) in [config file](./scripts/foundation-wallet-deployment/config.ts)
- run ```yarn verify:foundation-wallet ```
### Guide for deploying vesting wallets
Vesting wallets deployer script can be used to deploy vesting wallets. Script will deploy wallet factory contract, and then call `createWallets` function in a loop, 5 wallets at a time. Currently script does not contain logic for transfering tokens to deployed wallets, it only deploys wallets. Deployer script can handle failures, ie. if execution is unexpectedly terminated script can be re-run and it will continue deploying wallets which haven't been deployed. It is important to notice  assumption that input list of recipients does not change between runs.

Input for the script is list of recipients/beneficiaries and it should have following format:
```
{
  "0xbf7258ead721d9ecc04a8476cf4f863f1b754497": ["1", "340"],
  "0xb98637f3750707fe6d1f0b35dbaf5fc8de65c63d": ["2"],
  "0x28e7A8CD861E9fd6D253bffE80B0704752Fd6A0D": ["650", "1100", "2500"]
}
```
Input format defines beneficiary address as key and a list of token amounts as value. Actual token amounts are not used in script as atm we're not doing token transfers.

Output format containing deployed addresses will look like this:
```
{
  "vestingWalletFactory": "0x24067223381F042fF36fb87818196dB4D2C56E9B",
  "beneficiaries": [
    {
      "beneficiary": "0xbf7258Ead721d9eCC04a8476Cf4F863F1b754497",
      "walletAddresses": [
        "0x10956D45F1d221D3b98898d0e7af28C20541057F",
        "0xA10AF745eC1245fC61ed63f891ce6ee5D8E57Ba3"
      ]
    },
    {
      "beneficiary": "0xb98637f3750707FE6d1F0b35dbAF5fC8De65c63d",
      "walletAddresses": [
        "0xE54D680B7DCA2eb6761d0797a5247bD03FB7DF16"
      ]
    },
    {
      "beneficiary": "0x28e7A8CD861E9fd6D253bffE80B0704752Fd6A0D",
      "walletAddresses": [
        "0x1e4e5273cb79a55296CDe3351925ad6FbdFFDfe1",
        "0x7afD37b828dA31ea4313fAD334A4B7A5A7832489",
        "0xAd47B4D46d927C6A1150107A26FC4286b08eB5F2"
      ]
    }
  ]
}
```

Deployment steps:
- prepare `.env`, ie. `cp files/goerli/.env-sample .env`
  - `.env` shall include: `ARB_KEY`, `ARB_URL`, `VESTED_RECIPIENTS_FILE_LOCATION` and `DEPLOYED_WALLETS_FILE_LOCATION`
- prepare `vestingWalletRecipients.json` in a location which is pointed to by `VESTED_RECIPIENTS_FILE_LOCATION`
- run `yarn build`
- run deployer: `yarn deploy:vested-wallets`
- run verifier: `yarn verify:vested-wallets`

### Proposal Data Generator

`yarn gen:proposalData` can used to generate the data necessary to submit a proposal after a proposal's action contracts have been deployed.

 For descriptions of all command line options run 
 ```yarn gen:proposalData --help```

Example usage (for ArbOS11 upgrade AIP):


```
 yarn gen:proposalData 
 --govChainProviderRPC https://arb1.arbitrum.io/rpc 
 --actionChainIds 1 1 42161 42170 
 --actionAddresses 0x3b70f2da6f3b01f9a53dcbcb3e59ad3ad8bed924 0x54c2c372943572ac2a8e84d502ebc13f14b62246 0xF6c7Dc6eaE78aBF2f32df899654ca425Dfa99481 0x5357f4d3e8f8250a77bcddd5e58886ad1358220c 
 --pathToDescription ./scripts/proposals/ArbOS11AIP/description.txt 
 --writeToJsonPath ./scripts/proposals/ArbOS11AIP/data/ArbOS-11-AIP-data.json
 ```



