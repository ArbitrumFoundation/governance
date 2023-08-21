import { importDeployedContracts } from "../../../src-ts/utils";
import { Wallet } from "@ethersproject/wallet";
import { JsonRpcProvider } from "@ethersproject/providers";
import {
    SetSweepReceiverAction__factory,
    UpdateGasChargeAction__factory,
    UpdateL1CoreTimelockAction__factory,
    L1ArbitrumTimelock__factory
} from "../../../typechain-types";

import { ContractVerifier } from "../../contractVerifier";
import { utils } from "ethers";
import dotenv from "dotenv";
dotenv.config();

const abi = utils.defaultAbiCoder;

const mainnetDeployedContracts = importDeployedContracts("./files/mainnet/deployedContracts.json");
const mainnetTokenDistributor = "0x67a24CE4321aB3aF51c2D0a4801c3E111D88C9d9"
const newPerBatchGasCharge = 240000

const ARB_URL = process.env.ARB_URL;
const ARB_KEY = process.env.ARB_KEY;
const ARBISCAN_API_KEY = process.env.ARBISCAN_API_KEY;

const ETH_URL = process.env.ETH_URL;
const ETH_KEY = process.env.ETH_KEY;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;


if (!ARB_URL) throw new Error("ARB_URL required");
if (!ARB_KEY) throw new Error("ARB_KEY required");
if (!ARBISCAN_API_KEY) throw new Error("ARBISCAN_API_KEY required");

if (!ETH_URL) throw new Error("ETH_URL required");
if (!ETH_KEY) throw new Error("ETH_KEY required");
if (!ETHERSCAN_API_KEY) throw new Error("ETHERSCAN_API_KEY required");

const main = async () => {
    const l1Provider = new JsonRpcProvider(ETH_URL);
    const l1Deployer = new Wallet(ETH_KEY, l1Provider);

    const l2Provider = new JsonRpcProvider(ARB_URL);
    const l2Deployer = new Wallet(ARB_KEY, l2Provider);

    const { chainId: l1ChainId } = await l1Provider.getNetwork();
    const { chainId: l2ChainId } = await l2Provider.getNetwork();

    const deployedContracts = (() => {
        if (l2ChainId === 42161 && l1ChainId === 1) {
            return mainnetDeployedContracts;
        } else {
            throw new Error("Invalid ChainId");
        }
    })();

    const l1Verifier = new ContractVerifier(l1ChainId, ETHERSCAN_API_KEY, {});
    const l2Verifier = new ContractVerifier(l2ChainId, ARBISCAN_API_KEY, {});


    const action1 = await new SetSweepReceiverAction__factory(l2Deployer).deploy(
        deployedContracts.l2AddressRegistry,
        mainnetTokenDistributor
    );

    await action1.deployed();
    console.log("SetSweepReceiverAction deployed at", action1.address);

    await l2Verifier.verifyWithAddress(
        "SetSweepReceiverAction",
        action1.address,
        abi.encode(
            ["address", "address"],
            [deployedContracts.l2AddressRegistry, mainnetTokenDistributor]
        )
    );



    const action2 = await new UpdateGasChargeAction__factory(l2Deployer).deploy(
        newPerBatchGasCharge
    );

    await action2.deployed();
    console.log("UpdateGasChargeAction deployed at", action2.address);

    await l2Verifier.verifyWithAddress(
        "UpdateGasChargeAction",
        action2.address,
        abi.encode(["int64"], [newPerBatchGasCharge])
    );



    // layer 1 side

    const newTimelockLogic = await new L1ArbitrumTimelock__factory(l1Deployer).deploy();
    await newTimelockLogic.deployed()
    console.log("L1ArbitrumTimelock deployed at", newTimelockLogic.address);

    const action3 = await new UpdateL1CoreTimelockAction__factory(l1Deployer).deploy(
        deployedContracts.l1ProxyAdmin,
        deployedContracts.l1AddressRegistry,
        newTimelockLogic.address
    );

    await action3.deployed();
    console.log("UpdateL1CoreTimelockAction deployed at", action3.address);

    await l1Verifier.verifyWithAddress(
        "l1TimelockLogic",
        newTimelockLogic.address,
    );

    await l1Verifier.verifyWithAddress(
        "UpdateL1CoreTimelockAction",
        action3.address,
        abi.encode(
            ["address", "address", "address"],
            [
                deployedContracts.l1ProxyAdmin,
                deployedContracts.l1AddressRegistry,
                newTimelockLogic.address
            ]
        )
    );


};

main().then(() => {
    console.log("Done");
});
