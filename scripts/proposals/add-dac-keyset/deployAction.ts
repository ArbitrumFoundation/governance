import { importDeployedContracts } from "../../../src-ts/utils";
import { Wallet } from "@ethersproject/wallet";
import { JsonRpcProvider } from "@ethersproject/providers";
import {
    AddNovaKeysetAction__factory
} from "../../../typechain-types";

import { ContractVerifier } from "../../contractVerifier";
import dotenv from "dotenv";
dotenv.config();

const ETH_URL = process.env.ETH_URL;
const ETH_KEY = process.env.ETH_KEY;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

if (!ETH_URL) throw new Error("ETH_URL required");
if (!ETH_KEY) throw new Error("ETH_KEY required");
if (!ETHERSCAN_API_KEY) throw new Error("ETHERSCAN_API_KEY required");

const main = async () => {
    const l1Provider = new JsonRpcProvider(ETH_URL);
    const l1Deployer = new Wallet(ETH_KEY, l1Provider);

    const { chainId: l1ChainId } = await l1Provider.getNetwork();

    const l1Verifier = new ContractVerifier(l1ChainId, ETHERSCAN_API_KEY, {});

    // layer 1 side
    // the keyset added in that action can be verified using the instructions in
    // https://forum.arbitrum.foundation/t/non-emergency-security-council-action-update-arbitrum-nova-dac-keyset/19379
    const action = await new AddNovaKeysetAction__factory(l1Deployer).deploy();
    await action.deployed();
    console.log("AddNovaKeysetAction deployed at", action.address);

    await l1Verifier.verifyWithAddress(
        "AddNovaKeysetAction",
        action.address,
    );
};

main().then(() => {
    console.log("Done");
});
