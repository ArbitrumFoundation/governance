import { DeployedContracts } from "../../src-ts/types";
import { DeployParamsStruct } from "../../typechain-types/src/security-council-mgmt/factories/L2SecurityCouncilMgmtFactory";
import { Signer } from "ethers";

export interface SecurityCouncilAndChainID {
  securityCouncilAddress: string;
  chainID: number;
}

export interface ChainIDs {
  govChainID: number,
  l1ChainID: number,
}

export type ChainConfig = {
  chainID: number;
  rpcUrl: string;
  privateKey: string;
  prevEmergencySecurityCouncil: string;
}

export type GovernedChainConfig = ChainConfig & {
  upExecLocation: string;
}

export type GovernanceChainConfig = ChainConfig & {
  prevNonEmergencySecurityCouncil: string;
}

export type DeploymentConfig =
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
    emergencySignerThreshold: number;
    nonEmergencySignerThreshold: number;
    /** i.e. ArbOne */
    govChain: GovernanceChainConfig;
    /** i.e. Ethereum L1 */
    hostChain: ChainConfig;
    /** i.e. [Nova], governedChains DOES NOT include the governance chain (i.e. ArbOne) */
    governedChains: GovernedChainConfig[];
  };

export interface ChainIDToConnectedSigner {
  [key: number]: Signer;
}

export type SecurityCouncilManagementDeploymentResult = {
  keyValueStores: {[key: number]: string};
  securityCouncilMemberSyncActions: {[key: number]: string};

  emergencyGnosisSafes: {[key: number]: string};
  nonEmergencyGnosisSafe: string;

  nomineeElectionGovernor: string;
  nomineeElectionGovernorLogic: string;
  memberElectionGovernor: string;
  memberElectionGovernorLogic: string;
  securityCouncilManager: string;
  securityCouncilManagerLogic: string;
  securityCouncilMemberRemoverGov: string;
  securityCouncilMemberRemoverGovLogic: string;

  upgradeExecRouteBuilder: string;

  activationActionContracts: {[key: number]: string};

  l2SecurityCouncilMgmtFactory: string;
};