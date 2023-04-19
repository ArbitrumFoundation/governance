import { generateArbSysArgs } from "../../genGoverningChainTargetedProposalArgs"
import { JsonRpcProvider } from "@ethersproject/providers";
import { CoreGovPropposal } from "../coreGovProposalInterface";
import fs from 'fs'
import dotenv from "dotenv";
dotenv.config()
const { ARB_URL, ETH_URL } = process.env;
if (!ARB_URL) throw new Error("ARB_URL required");
if(!ETH_URL) throw new Error("ETH_URL required");

const chainIDToActionAddress =  {
    42161: "",
    421613: "0x457b79f1bb94f0af8b8d0c2a0a535fd0c8ded3ea",
}


const description = `
TODO
`
const main = async ()=>{
    const l1Provider = new JsonRpcProvider(ETH_URL);
    const l2Provider = new JsonRpcProvider(ARB_URL)
    const chainId  =  (await l2Provider.getNetwork()).chainId as 42161 | 421613
    const actionAddress = chainIDToActionAddress[chainId]
    if(!actionAddress) throw new Error("Invalid chainId")

    const { l1TimelockTo, l1TimelockScheduleCallData } =  await generateArbSysArgs(l1Provider, l2Provider, actionAddress, description)
    const proposal:CoreGovPropposal = {
        actionChainID: chainId,
        actionAddress,
        description,
        arbSysSendTxToL1Args: {
            l1Timelock: l1TimelockTo,
            calldata: l1TimelockScheduleCallData
        }

    }
    const path = `${__dirname}/data/${chainId}-AIP1.2-data.json`
    fs.writeFileSync(path, JSON.stringify(proposal))
    console.log('Wrote proposal data to ', path);
    
    console.log(proposal);

    
}

main().then(() => {
    console.log('done');
    
})