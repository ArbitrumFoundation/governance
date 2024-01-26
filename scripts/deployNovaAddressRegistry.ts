import { Wallet } from "@ethersproject/wallet";
import { JsonRpcProvider } from "@ethersproject/providers";
import { L1AddressRegistry__factory } from "../typechain-types";

import { ContractVerifier } from "./contractVerifier";
import dotenv from "dotenv";
import { utils } from "ethers";
const abi = utils.defaultAbiCoder;

dotenv.config();

const ETH_URL = process.env.ETH_URL;
const ETH_KEY = process.env.ETH_KEY;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

if (!ETH_URL) throw new Error("ETH_URL required");
if (!ETH_KEY) throw new Error("ETH_KEY required");
if (!ETHERSCAN_API_KEY) throw new Error("ETHERSCAN_API_KEY required");

const main = async () => {
  const l1Provider = new JsonRpcProvider(ETH_URL);
  const signer = new Wallet(ETH_KEY, l1Provider);

  const l1Verifier = new ContractVerifier(1, ETHERSCAN_API_KEY, {});

  const NOVA_INBOX = "0xc4448b71118c9071Bcb9734A0EAc55D18A153949";
  const L1_GOV_TIMELOCK = "0xE6841D92B0C345144506576eC13ECf5103aC7f49";
  const NOVA_L1_CUSTOM_GATEWAY = "0x23122da8C581AA7E0d07A36Ff1f16F799650232f";
  const NOVA_L1_GATEWAY_ROUTER = "0xC840838Bc438d73C16c2f8b22D2Ce3669963cD48";

    const novaL1AddressRegistry = await new L1AddressRegistry__factory(signer).deploy(
      NOVA_INBOX, // nova inbox
      L1_GOV_TIMELOCK, // l1 gov timelock
      NOVA_L1_CUSTOM_GATEWAY, // nova l1 custom gateway
      NOVA_L1_GATEWAY_ROUTER // nova l1 gateway router
    );
    await novaL1AddressRegistry.deployed();
    console.log("L1AddressRegistry deployed at", novaL1AddressRegistry.address);

  await l1Verifier.verifyWithAddress(
    "L1AddressRegistry",
    novaL1AddressRegistry.address,
    abi.encode(
      ["address", "address", "address", "address"],
      [NOVA_INBOX, L1_GOV_TIMELOCK, NOVA_L1_CUSTOM_GATEWAY, NOVA_L1_GATEWAY_ROUTER]
    )
  );
};

main().then(() => {
  console.log("Done");
});
