import { RoundTripProposalCreator, L2GovConfig, L1GovConfig, UpgradeConfig } from "../src-ts/proposalCreator"
import { JsonRpcProvider } from "@ethersproject/providers";
import dotenv from "dotenv";
dotenv.config();
const main = async () => {
    const l1Provider = new JsonRpcProvider(process.env.ETH_URL)
    const l2Provider = new JsonRpcProvider(process.env.ARB_URL)

    const L2GovConfig: L2GovConfig = {
        governorAddr: "0xf07DeD9dC292157749B6Fd268E37DF6EA38395B9",
        provider: l2Provider,
    }

    const  L1GovConfig: L1GovConfig = {
        timelockAddr: "0xE6841D92B0C345144506576eC13ECf5103aC7f49",
        provider: l1Provider,
    }

    const upgradeConfig: UpgradeConfig = {
        upgradeExecutorAddr: "0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827",
        provider: l2Provider,
    }

    const proposalCreator = new RoundTripProposalCreator(L1GovConfig, [upgradeConfig])

    const description = `
    This proposal sets the minimum threshold for proposal submission to 5,000,000 delegated votes. This is intended to minimize proposal-spam. 
    The proposal threshold was initially mistakenly set to a lower value; in this proposal, the value is re-set to the value specified in the 
    Constitution of the Arbitrum DAO (constitution hash: 0x5e5d9153e6d9b0c1e88187d31468f0a7fa096aff9f4d538d27619798db6522e7).
    The proposal was submitted via the slow non-emergency security council path, since the upgrade is routine and unlikely to elicit objections 
    (it aligns the contracts values with those already in the constitution) and isn't security-critical.
    `
    const args = await  proposalCreator.createTimelockScheduleArgs(L2GovConfig, ["0x8f89288a199f92cd6c5c9fd97b530ea5e8685563"], description)
    console.log(args);
    
}

main().then(()=> console.log("done"));
