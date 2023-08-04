import { DeployedContracts } from "../../src-ts/types";
import { ChainAndUpExecLocationStruct, DeployParamsStruct } from "../../typechain-types/src/security-council-mgmt/factories/L2SecurityCouncilMgmtFactory";
import { Signer } from "ethers";

export interface SecurityCouncilAndChainID {
  securityCouncilAddress: string;
  chainID: number;
}

export interface ChainIDs {
  govChainID: number,
  l1ChainID: number,
}
export interface DeploymentConfig {
  mostDeployParams: Omit<DeployParamsStruct, "securityCouncils" | "l1TimelockMinDelay">;
  securityCouncils: SecurityCouncilAndChainID[];
  chainIDs: ChainIDs
}


export type ChainConfig = {
  chainID: number;
  rpcUrl: string;
  privateKey: string;
}

export type GovernedChainConfig = ChainConfig & {
  upExecLocation: string;
}

export type UserSpecifiedConfig =
  DeployedContracts &
  Pick<
    DeployParamsStruct,
    'removalGovVotingDelay' |
    'removalGovVotingPeriod' |
    'removalGovQuorumNumerator' |
    'removalGovProposalThreshold' |
    'removalGovVoteSuccessNumerator' |
    'removalGovMinPeriodAfterQuorum' |
    'removalProposalExpirationBlocks' |
    'firstNominationStartDate' |
    'nomineeVettingDuration' |
    'nomineeVetter' |
    'nomineeQuorumNumerator' |
    'nomineeVotingPeriod' |
    'memberVotingPeriod' |
    'fullWeightDuration' |
    'firstCohort' |
    'secondCohort'
  > & {
    govChain: ChainConfig;
    hostChain: ChainConfig;
    governedChains: GovernedChainConfig[];
  };

export interface ChainIDToConnectedSigner {
  [key: number]: Signer;
}