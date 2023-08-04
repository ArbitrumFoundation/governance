import { ethers } from "ethers";
import { DeployedContracts } from "../../../src-ts/types";
import { UserSpecifiedConfig } from "../types";
import * as fs from "fs";

const deployedContracts = JSON.parse(
    fs.readFileSync("./files/mainnet/deployedContracts.json").toString()
) as DeployedContracts;

function daysToBlocks(days: number) {
    return secondsToBlocks(days * 24 * 60 * 60);
}

function secondsToBlocks(seconds: number) {
    return Math.floor(seconds / 12);
}

function assertDefined<T>(val: T | undefined): T {
    if (val === undefined) {
        throw new Error("value is undefined");
    }
    return val;
}

const config: UserSpecifiedConfig = {
    ...deployedContracts,
    removalGovVotingDelay: 21600,
    removalGovVotingPeriod: 100800,
    removalGovQuorumNumerator: 1000,
    removalGovProposalThreshold: ethers.utils.parseEther("1000000"),
    removalGovVoteSuccessNumerator: 8333,
    removalGovMinPeriodAfterQuorum: 14400,
    removalProposalExpirationBlocks: 0, // todo 
    firstNominationStartDate: {
        year: 2023,
        month: 9,
        day: 15,
        hour: 12, // todo
    },
    nomineeVettingDuration: daysToBlocks(14),
    nomineeVetter: "0x000000000000000000000000000000000000dead", // todo
    nomineeQuorumNumerator: 20, // 0.2%
    nomineeVotingPeriod: daysToBlocks(7),
    memberVotingPeriod: daysToBlocks(21),
    fullWeightDuration: daysToBlocks(7),
    firstCohort: [
        "0x526C0DA9970E7331d171f86AeD28FAFB5D8A49EF",
        "0xf8e1492255d9428c2Fc20A98A1DeB1215C8ffEfd",
        "0x0E5011001cF9c89b0259BC3B050785067495eBf5",
        "0x8688515028955734350067695939423222009623",
        "0x6e77068823f9D0fE98F80764c21Ec294e4d96AdB",
        "0x8e6247239CBeB3Eaf9d9a691D01A67e2A9Fea3C5",
    ],
    secondCohort: [
        "0x566a07C3c932aE6AF74d77c29e5c30D8B1853710",
        "0x5280406912EB8Ec677Df66C326BE48f938DC2e44",
        "0x0275b3D54a5dDbf8205A75984796eFE8b7357Bae",
        "0x5A1FD562271aAC2Dadb51BAAb7760b949D9D81dF",
        "0xf6B6F07862A02C85628B3A9688beae07fEA9C863",
        "0x475816ca2a31D601B4e336f5c2418A67978aBf09",
    ],
    govChain: {
        chainID: 42161,
        rpcUrl: assertDefined(process.env.ARBITRUM_RPC_URL),
        privateKey: assertDefined(process.env.PRIVATE_KEY),
    },
    hostChain: {
        chainID: 1,
        rpcUrl: assertDefined(process.env.MAINNET_RPC_URL),
        privateKey: assertDefined(process.env.PRIVATE_KEY),
    },
    governedChains: [
        {
            chainID: 42170,
            rpcUrl: assertDefined(process.env.NOVA_RPC_URL),
            privateKey: assertDefined(process.env.PRIVATE_KEY),
            // @ts-ignore
            upExecLocation: deployedContracts.novaUpgradeExecutorProxy,
        }
    ]
};

export default config;
