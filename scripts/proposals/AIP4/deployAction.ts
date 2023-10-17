import { importDeployedContracts } from "../../../src-ts/utils";
import { Wallet } from "@ethersproject/wallet";
import { JsonRpcProvider } from "@ethersproject/providers";
import { AIP4Action__factory } from "../../../typechain-types";
import { ContractVerifier } from "../../contractVerifier";
import { utils } from "ethers";
import dotenv from "dotenv";
dotenv.config();

const abi = utils.defaultAbiCoder;

const goerliDeployedContracts = importDeployedContracts("./files/goerli/deployedContracts.json");
const mainnetDeployedContracts = importDeployedContracts("./files/mainnet/deployedContracts.json");

const ARB_URL = process.env.ARB_URL;
const ARB_KEY = process.env.ARB_KEY;
const ARBISCAN_API_KEY = process.env.ARBISCAN_API_KEY;

if (!ARB_URL) throw new Error("ARB_URL required");
if (!ARB_KEY) throw new Error("ARB_KEY required");
if (!ARBISCAN_API_KEY) throw new Error("ARBISCAN_API_KEY required");

const main = async () => {
  const l2Provider = new JsonRpcProvider(ARB_URL);
  const deployer = new Wallet(ARB_KEY, l2Provider);

  const { chainId } = await l2Provider.getNetwork();
  const deployedContracts = (() => {
    if (chainId === 421613) {
      return goerliDeployedContracts;
    } else if (chainId === 42161) {
      return mainnetDeployedContracts;
    } else {
      throw new Error("Invalid chainId");
    }
  })();
  const verifier = new ContractVerifier(chainId, ARBISCAN_API_KEY, {});

  const action = await new AIP4Action__factory(deployer).deploy(
    deployedContracts.l2AddressRegistry
  );

  await action.deployed();
  console.log("AIP4 deployed at", action.address);

  await verifier.verifyWithAddress(
    "AIP4Action",
    action.address,
    abi.encode(["address"], [deployedContracts.l2AddressRegistry])
  );
};

main().then(() => {
  console.log("Done");
});
