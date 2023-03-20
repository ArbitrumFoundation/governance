import {
  L1AddressRegistry__factory,
  L1SetInitialGovParamsAction__factory,
  ArbGoerliSetInitialGovParamsAction__factory,
  ArbOneGovAddressRegistry__factory,
} from "../typechain-types";
import { Wallet, utils } from "ethers";
import { JsonRpcProvider } from "@ethersproject/providers";

import { ContractVerifier } from "./ContractVerifier";
import dotenv from "dotenv";
const abi = utils.defaultAbiCoder;

const GOERLI_ROLLUP_INBOX = "0x6BEbC4925716945D46F0Ec336D5C2564F419682C";
const GOERLI_ROLLUP_GOV_L1_TIMELOCK = "0x364188EcF8E0733cB90d8EbeD90d56E56205dDfE";
const GOERLI_ROLLUP_CORE_GOV = "0xa584d185244DCbCa8A98dBdB4e550a5De3A64c81";
const GOERLI_ROLLUP_TREASURY_GOV = "0x5C7f047cC1564b120DEabFC29B67c60a7c6d6BD2";
const GOERLI_ROLLUP_TREASURY_WALLET = "0xDA4d3D030B469c3D42B0613202341a6b00E8836e";

dotenv.config();

const l1RPC = "https://goerli.infura.io/v3/8838d00c028a46449be87e666387c71a";
const L2_RPC = "https://goerli-rollup.arbitrum.io/rpc";
const apiKey = process.env.ETHERSCAN_KEY;
const l1Key = process.env.ETH_KEY as string;
const l2Key = process.env.ARB_KEY as string;
if (!apiKey) {
  throw new Error("Set ETHERSCAN_KEY");
}

const main = async () => {
  const l1Deployer = new Wallet(l1Key, new JsonRpcProvider(l1RPC));
  const l1Verifier = new ContractVerifier(5, apiKey, {});

  const l2Deployer = new Wallet(l2Key, new JsonRpcProvider(L2_RPC));
  const l2Verifier = new ContractVerifier(421613, apiKey, {});

  const l1AddressRegistryFactory = new L1AddressRegistry__factory().connect(l1Deployer);
  const l1AddressRegistry = await l1AddressRegistryFactory.deploy(
    GOERLI_ROLLUP_INBOX,
    GOERLI_ROLLUP_GOV_L1_TIMELOCK
  );
  await l1AddressRegistry.deployed();
  console.log("L1AddressRegistry", l1AddressRegistry.address);

  await l1Verifier.verifyWithAddress(
    "L1AddressRegistry",
    l1AddressRegistry.address,
    abi.encode(["address", "address"], [GOERLI_ROLLUP_INBOX, GOERLI_ROLLUP_GOV_L1_TIMELOCK])
  );

  const setGovL1ParamsFactory = new L1SetInitialGovParamsAction__factory().connect(l1Deployer);
  const setL1GovParams = await setGovL1ParamsFactory.deploy(l1AddressRegistry.address);
  await setL1GovParams.deployed();
  console.log("L1SetInitialGovParamsAction", setL1GovParams.address);

  await l1Verifier.verifyWithAddress(
    "L1SetInitialGovParamsAction",
    setL1GovParams.address,
    abi.encode(["address"], [l1AddressRegistry.address])
  );

  const l2GovRegistryFactory = new ArbOneGovAddressRegistry__factory().connect(l2Deployer);
  const l2GovRegistry = await l2GovRegistryFactory.deploy(
    GOERLI_ROLLUP_CORE_GOV,
    GOERLI_ROLLUP_TREASURY_GOV,
    GOERLI_ROLLUP_TREASURY_WALLET
  );
  await l2GovRegistry.deployed();
  console.log("ArbOneGovAddressRegistry", l2GovRegistry.address);
  await l2Verifier.verifyWithAddress(
    "ArbOneGovAddressRegistry",
    l2GovRegistry.address,
    abi.encode(
      ["address", "address", "address"],
      [GOERLI_ROLLUP_CORE_GOV, GOERLI_ROLLUP_TREASURY_GOV, GOERLI_ROLLUP_TREASURY_WALLET]
    )
  );

  const setL2GovParamsFactory = new ArbGoerliSetInitialGovParamsAction__factory().connect(
    l2Deployer
  );
  const setL2GovParams = await setL2GovParamsFactory.deploy(l2GovRegistry.address);
  await setL2GovParams.deployed();
  console.log("ArbGoerliSetInitialGovParams", setL2GovParams.address);

  await l2Verifier.verifyWithAddress(
    "ArbGoerliSetInitialGovParamsAction",
    setL2GovParams.address,
    abi.encode(["address"], [l2GovRegistry.address])
  );
};

main().then(() => console.log("Done."));
