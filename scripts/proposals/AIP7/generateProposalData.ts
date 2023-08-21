import { generateArbSysArgs } from "../../genGoverningChainTargetedProposalArgs";
import { JsonRpcProvider } from "@ethersproject/providers";
import { CoreGovPropposal } from "../coreGovProposalInterface";
import fs from "fs";
import dotenv from "dotenv";
import { RoundTripProposalCreator, L1GovConfig, UpgradeConfig } from "../../../src-ts/proposalCreator";
import { importDeployedContracts } from "../../../src-ts/utils";
import { BigNumber, utils } from "ethers";
dotenv.config();

const ARB_URL = process.env.ARB_URL;
const ARB_KEY = process.env.ARB_KEY;

const ETH_URL = process.env.ETH_URL;
const ETH_KEY = process.env.ETH_KEY;


if (!ARB_URL) throw new Error("ARB_URL required");
if (!ARB_KEY) throw new Error("ARB_KEY required");

if (!ETH_URL) throw new Error("ETH_URL required");
if (!ETH_KEY) throw new Error("ETH_KEY required");

const mainnetDeployedContracts = importDeployedContracts("./files/mainnet/deployedContracts.json");

const main = async () => {
    const l1Provider = new JsonRpcProvider(ETH_URL);
    const l2Provider = new JsonRpcProvider(ARB_URL);

    const { chainId: l1ChainId } = await l1Provider.getNetwork();
    const { chainId: l2ChainId } = await l2Provider.getNetwork();


    const deployedContracts = (() => {
        if (l2ChainId === 42161 && l1ChainId === 1) {
            return mainnetDeployedContracts;
        } else {
            throw new Error("Invalid ChainId");
        }
    })();

    const { l1Timelock, l2Executor, l1Executor } = deployedContracts;

    const l2ActionAddress1 = "0x7b1247f443359d1447cf25e73380bc9b99f2628f"; // UpdateGasChargeAction
    const l2ActionAddress2 = "0xbaba4daf5800b9746f58c724f05e03880850d578"; // SetSweepReceiverAction
    const l1ActionAddress1 = "0xbaba4daf5800b9746f58c724f05e03880850d578"; // UpdateL1CoreTimelockAction

    const L1GovConfig: L1GovConfig = {
        timelockAddr: l1Timelock,
        provider: l1Provider,
    };

    const upgradeConfigL2: UpgradeConfig = {
        upgradeExecutorAddr: l2Executor,
        provider: l2Provider,
    };
    const upgradeConfigL1: UpgradeConfig = {
        upgradeExecutorAddr: l1Executor,
        provider: l1Provider,
    };

    const upgradeValue = BigNumber.from(0);
    const actionIface = new utils.Interface(["function perform() external"]);
    const upgradeData = actionIface.encodeFunctionData("perform", []);
    const description = "Security council non emergency upgrade August 2023";


    const proposalCreator = new RoundTripProposalCreator(L1GovConfig, [upgradeConfigL2, upgradeConfigL2, upgradeConfigL1]);

    const prop = await proposalCreator.createRoundTripCallDataForArbSysCall(
        [
            l2ActionAddress1, l2ActionAddress2, l1ActionAddress1
        ],
        [
            upgradeValue, upgradeValue, upgradeValue
        ],
        [
            upgradeData, upgradeData, upgradeData
        ],
        description
    );


    const proposal: CoreGovPropposal = {
        actionChainID: [42161, 42161, 1],
        actionAddress: [l2ActionAddress1, l2ActionAddress2, l1ActionAddress1],
        description,
        arbSysSendTxToL1Args: {
            l1Timelock: prop.l1TimelockTo,
            calldata: prop.l1TimelockScheduleCallData,
        },
    };

    const path = `${__dirname}/data/42161-AIP7-data.json`;
    fs.writeFileSync(path, JSON.stringify(proposal, null, 2));
    console.log("Wrote proposal data to", path);
    console.log(proposal);
};

main().then(() => {
    console.log("done");
});


