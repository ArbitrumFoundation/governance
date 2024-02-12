import { importDeployedContracts } from "../../../src-ts/utils";
import { Wallet } from "@ethersproject/wallet";
import { JsonRpcProvider } from "@ethersproject/providers";
import { ArbOS20Action__factory } from "../../../typechain-types";
import { ContractVerifier } from "../../contractVerifier";
import { utils, constants } from "ethers";
import dotenv from "dotenv";
dotenv.config();

const abi = utils.defaultAbiCoder;

const goerliDeployedContracts = importDeployedContracts("./files/goerli/deployedContracts.json");
const mainnetDeployedContracts = importDeployedContracts("./files/mainnet/deployedContracts.json");

const newWasmModuleRoot = utils.keccak256(constants.HashZero) // TODO: Replace new wasm module root
// https://github.com/OffchainLabs/nitro-contracts/pull/140
const goerliArbOS20Contracts = {
  "newSequencerInbox": "0x883432332706a689C81623fD9B74E5b3ac2D48F9",
  "newOSP": "0x7450fD357b9aE8748B299f5124468CE7Aab3b0e5",
  "newChallengeManager": "0x0399190e0c0702e19A2689a78Cd06B51b7E67B7D"
}
const mainnetArbOS20Contracts = {
  "newSequencerInbox": "0x31DA64D19Cd31A19CD09F4070366Fe2144792cf7",
  "newOSP": "0xC6E1E6dB03c3F475bC760FE20ed93401EC5c4F7e",
  "newChallengeManager": "0xE129b8Aa61dF65cBDbAE4345eE3fb40168DfD566"
}

const ARB_URL = process.env.ARB_URL;
const ETH_URL = process.env.ETH_URL;
const ETH_KEY = process.env.ETH_KEY;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

if (!ARB_URL) throw new Error("ARB_URL required");
if (!ETH_URL) throw new Error("ETH_URL required");
if (!ETH_KEY) throw new Error("ETH_KEY required");
if (!ETHERSCAN_API_KEY) throw new Error("ETHERSCAN_API_KEY required");

const main = async () => {
  const l1Provider = new JsonRpcProvider(ETH_URL);
  const l1Deployer = new Wallet(ETH_KEY, l1Provider);

  const l2Provider = new JsonRpcProvider(ARB_URL);

  const { chainId: l1ChainId } = await l1Provider.getNetwork();
  const { chainId: l2ChainId } = await l2Provider.getNetwork();

  const { deployedContracts, upgradeContracts } = (() => {
    if (l2ChainId === 421613 && l1ChainId === 5) {
      return { deployedContracts: goerliDeployedContracts, upgradeContracts: goerliArbOS20Contracts };
    } else if (l2ChainId === 42161 && l1ChainId === 1) {
      return { deployedContracts: mainnetDeployedContracts, upgradeContracts: mainnetArbOS20Contracts };
    } else {
      throw new Error("Invalid chainId");
    }
  })();
  const verifier = new ContractVerifier(l1ChainId, ETHERSCAN_API_KEY, {});

  const constructorArgs: [string, string, string, string, string, string] = [
    deployedContracts.l1AddressRegistry,
    newWasmModuleRoot,
    upgradeContracts.newSequencerInbox,
    upgradeContracts.newChallengeManager,
    deployedContracts.l1ProxyAdmin,
    upgradeContracts.newOSP
  ]

  const action = await new ArbOS20Action__factory(l1Deployer).deploy(
    ...constructorArgs
  );
  await action.deployed();
  console.log("ArbOS20Action deployed at", action.address);

  await verifier.verifyWithAddress(
    "ArbOS20Action",
    action.address,
    abi.encode(["address", "bytes32", "address", "address", "address", "address"], constructorArgs)
  );
};

main().then(() => {
  console.log("Done");
});
