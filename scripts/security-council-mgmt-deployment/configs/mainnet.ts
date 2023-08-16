import { ethers } from "ethers";
import { DeploymentConfig } from "../types";
import { assertDefined, blocks, readDeployedContracts } from "../utils";
import dotenv from "dotenv";
dotenv.config();

const deployedContracts = readDeployedContracts("./files/mainnet/deployedContracts.json");

const config: DeploymentConfig = {
  ...deployedContracts,
  emergencySignerThreshold: 9,
  nonEmergencySignerThreshold: 7,
  removalGovVotingDelay: blocks(3, 'days'),
  removalGovVotingPeriod: blocks(14, 'days'),
  removalGovQuorumNumerator: 1000, // 10%
  removalGovProposalThreshold: ethers.utils.parseEther("1000000"),
  removalGovVoteSuccessNumerator: 8333, // 83.33%
  removalGovMinPeriodAfterQuorum: blocks(2, 'days'),
  removalProposalExpirationBlocks: blocks(14, 'days'),
  firstNominationStartDate: {
    year: 2023,
    month: 9,
    day: 15,
    hour: 12,
  },
  nomineeVettingDuration: blocks(14, 'days'),
  nomineeVetter: "0xc610984d9C96a7CE54Bcd335CEee9b0e3874380C",
  nomineeQuorumNumerator: 20, // 0.2%
  nomineeVotingPeriod: blocks(7, 'days'),
  memberVotingPeriod: blocks(21, 'days'),
  fullWeightDuration: blocks(7, 'days'),
  firstCohort: [
    "0x526C0DA9970E7331d171f86AeD28FAFB5D8A49EF",
    "0xf8e1492255d9428c2Fc20A98A1DeB1215C8ffEfd",
    "0x0E5011001cF9c89b0259BC3B050785067495eBf5",
    "0x8688515028955734350067695939423222009623",
    "0x88910996671162953E89DdcE5C8137f9077da217",
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
    rpcUrl: assertDefined(process.env.ARB_URL, "ARB_URL is undefined"),
    privateKey: assertDefined(process.env.ARB_KEY, "ARB_KEY is undefined"),
    prevEmergencySecurityCouncil: "0x3568A44b3E72F5B17a0E14E53fdB7366B3B7Ad13",
    prevNonEmergencySecurityCouncil: "0x895c9fc6bcf06e553b54A9fE11D948D67a9B76FA",
  },
  hostChain: {
    chainID: 1,
    rpcUrl: assertDefined(process.env.ETH_URL, "ETH_URL is undefined"),
    privateKey: assertDefined(process.env.ETH_KEY, "ETH_KEY is undefined"),
    prevEmergencySecurityCouncil: "0x3666a60ff589873ced457a9a8a0aA6F83D708767",
  },
  governedChains: [
    {
      chainID: 42170,
      rpcUrl: assertDefined(process.env.NOVA_URL, "NOVA_URL is undefined"),
      privateKey: assertDefined(process.env.NOVA_KEY, "NOVA_KEY is undefined"),
      // @ts-ignore
      upExecLocation: deployedContracts.novaUpgradeExecutorProxy,
      prevEmergencySecurityCouncil: "0x3cA27a792C64a3a81417499AA53786A41812B2cd",
    }
  ]
};

export default config;
