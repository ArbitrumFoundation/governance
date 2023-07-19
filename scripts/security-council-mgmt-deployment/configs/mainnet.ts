import { DeploymentConfig } from "../types";
import {  getL2Network } from "@arbitrum/sdk";
import { constants } from "ethers";
import { DeployedContracts } from "../../../src-ts/types";
import fs from "fs";
import dotenv from "dotenv";
dotenv.config();

export const getMainnetConfig = async () => {
  const l1Id = 1;
  const arbOneId = 42161;
  const novaId = 42170;

  const arbOne = await getL2Network(arbOneId);
  const nova = await getL2Network(novaId);
  const mainnetCoreGovContracts = JSON.parse(
    fs.readFileSync("./files/mainnet/deployedContracts.json").toString()
  ) as DeployedContracts;

  const mainnetConfig: DeploymentConfig = {
    mostDeployParams: {
      upgradeExecutors: [
        {
          chainId: l1Id,
          location: {
            inbox: constants.AddressZero,
            upgradeExecutor: mainnetCoreGovContracts.l1Executor,
          },
        },
        {
          chainId: arbOneId,
          location: {
            inbox: arbOne.ethBridge.inbox,
            upgradeExecutor: mainnetCoreGovContracts.l2Executor,
          },
        },
        {
          chainId: novaId,
          location: {
            inbox: nova.ethBridge.inbox,
            // @ts-ignore
            upgradeExecutor: mainnetCoreGovContracts.novaUpgradeExecutorProxy,
          },
        },
      ],
      govChainEmergencySecurityCouncil: "TODO",
      l1ArbitrumTimelock: mainnetCoreGovContracts.l1Timelock,
      l2CoreGovTimelock: mainnetCoreGovContracts.l2CoreTimelock,
      govChainProxyAdmin: mainnetCoreGovContracts.l2ProxyAdmin,
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
      l2UpgradeExecutor: mainnetCoreGovContracts.l2Executor,
      arbToken: mainnetCoreGovContracts.l2Token,
      removalGovVotingDelay: 21600, // same as core gov
      removalGovVotingPeriod: 100800, // same as core gov
      removalGovQuorumNumerator: 1000, // 10%
      removalGovProposalThreshold: 1000000, // same as core gov
      removalGovVoteSuccessNumerator: 8333,
      removalGovMinPeriodAfterQuorum: 14400, // same as core gov
      firstNominationStartDate: {
        year: "TODO",
        month: "TODO",
        day: "TODO",
        hour: "TODO",
      },
      nomineeVettingDuration: 0, // TODO
      nomineeVetter: "0xTODO",
      nomineeQuorumNumerator: 0, // TODO
      nomineeVotingPeriod: 0, // TODO
      memberVotingPeriod: 0, // TODO
      fullWeightDuration: 0, // TODO
    },
    securityCouncils: [
      {
        securityCouncilAddress: "0xTODO",
        chainID: l1Id,
      },
      {
        securityCouncilAddress: "0xTODO",
        chainID: arbOneId,
      },
      {
        securityCouncilAddress: "0xTODO",
        chainID: novaId,
      },
    ],
    chainIDs: {
      govChainID: arbOneId,
      l1ChainID: l1Id,
    },
  };
  return mainnetConfig;
};
