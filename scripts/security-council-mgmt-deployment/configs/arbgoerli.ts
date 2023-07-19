import { DeploymentConfig } from "../types";
import { getL2Network } from "@arbitrum/sdk";
import { constants } from "ethers";
import { DeployedContracts } from "../../../src-ts/types";
import fs from "fs";
import dotenv from "dotenv";
dotenv.config();

export const getGoerliConfig = async () => {
  const l1Id = 5;
  const arbGoerliID = 421613;

  const arbGoerli = await getL2Network(arbGoerliID);
  const goerliCoreGovContracts = JSON.parse(
    fs.readFileSync("./files/goerli/deployedContracts.json").toString()
  ) as DeployedContracts;

  const goerliConfig: DeploymentConfig = {
    mostDeployParams: {
      upgradeExecutors: [
        {
          chainId: l1Id,
          location: {
            inbox: constants.AddressZero,
            upgradeExecutor: goerliCoreGovContracts.l1Executor,
          },
        },
        {
          chainId: arbGoerliID,
          location: {
            inbox: arbGoerli.ethBridge.inbox,
            upgradeExecutor: goerliCoreGovContracts.l2Executor,
          },
        },
      ],
      govChainEmergencySecurityCouncil: "TODO",
      l1ArbitrumTimelock: goerliCoreGovContracts.l1Timelock,
      l2CoreGovTimelock: goerliCoreGovContracts.l2CoreTimelock,
      govChainProxyAdmin: goerliCoreGovContracts.l2ProxyAdmin,
      firstCohort: [
        // TODO
      ],
      secondCohort: [
        //    TODO
      ],
      l2UpgradeExecutor: goerliCoreGovContracts.l2Executor,
      arbToken: goerliCoreGovContracts.l2Token,
      removalGovVotingDelay: 0, // TODO
      removalGovVotingPeriod: 0, // TODO
      removalGovQuorumNumerator: 0, // TODO
      removalGovProposalThreshold: 0, // TODO
      removalGovVoteSuccessNumerator: 0, // TODO
      removalGovMinPeriodAfterQuorum: 0, // TODO
      firstNominationStartDate: {
        year: "TODO",
        month: "TODO",
        day: "TODO",
        hour: "TODO",
      },
      nomineeVettingDuration: 0, // TODO
      nomineeVetter: "TODO",
      nomineeQuorumNumerator: 0, // TODO
      nomineeVotingPeriod: 0, // TODO
      memberVotingPeriod: 0, // TODO
      fullWeightDuration: 0, // TODO
    },
    securityCouncils: [
      {
        securityCouncilAddress: "TOOD",
        chainID: l1Id,
      },
      {
        securityCouncilAddress: "TOOD",
        chainID: arbGoerliID,
      },
    ],
    chainIDs: {
      govChainID: arbGoerliID,
      l1ChainID: l1Id,
    },
  };
  return goerliConfig;
};
