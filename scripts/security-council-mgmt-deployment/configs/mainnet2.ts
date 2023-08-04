import { DeployedContracts } from "../../../src-ts/types";
import { UserSpecifiedConfig } from "../types";
import * as fs from "fs";

const deployedContracts = JSON.parse(
    fs.readFileSync("./files/mainnet/deployedContracts.json").toString()
) as DeployedContracts;

export default {
    ...deployedContracts,
    removalGovVotingDelay: 0,
    removalGovVotingPeriod: 0,
    removalGovQuorumNumerator: 0,
    removalGovProposalThreshold: 0,
    removalGovVoteSuccessNumerator: 0,
    removalGovMinPeriodAfterQuorum: 0,
    removalProposalExpirationBlocks: 0,
    firstNominationStartDate: {
        year: 0,
        month: 0,
        day: 0,
        hour: 0,
    },
    nomineeVettingDuration: 0,
    nomineeVetter: "",
    nomineeQuorumNumerator: 0,
    nomineeVotingPeriod: 0,
    memberVotingPeriod: 0,
    fullWeightDuration: 0,
    firstCohort: [],
    secondCohort: [],
    govChain: {
        chainID: 0,
        rpcUrl: "",
        privateKey: "",
    },
    hostChain: {
        chainID: 0,
        rpcUrl: "",
        privateKey: "",
    },
    governedChains: [
        {
            chainID: 0,
            rpcUrl: "",
            privateKey: "",
            upExecLocation: "",
        }
    ]
} satisfies UserSpecifiedConfig;
