import { importDeployedContracts } from "../src-ts/utils";
import { Wallet } from "@ethersproject/wallet";
import { JsonRpcProvider } from "@ethersproject/providers";
import { L2AddressRegistry__factory } from "../typechain-types";
import { ContractVerifier } from "./contractVerifier";
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

  const l2AddressRegistry = await new L2AddressRegistry__factory(deployer).deploy(
    deployedContracts.l2CoreGoverner,
    deployedContracts.l2TreasuryGoverner,
    deployedContracts.l2ArbTreasury,
    deployedContracts.arbitrumDAOConstitution
  );
  await l2AddressRegistry.deployed();
  console.log("L2AddressRegistry deployed at", l2AddressRegistry.address);

  await verifier.verifyWithAddress(
    "L2AddressRegistry",
    l2AddressRegistry.address,
    abi.encode(
      ["address", "address", "address", "address"],
      [
        deployedContracts.l2CoreGoverner,
        deployedContracts.l2TreasuryGoverner,
        deployedContracts.l2ArbTreasury,
        deployedContracts.arbitrumDAOConstitution,
      ]
    )
  );
};

main().then(() => {
  console.log("Done");
});
