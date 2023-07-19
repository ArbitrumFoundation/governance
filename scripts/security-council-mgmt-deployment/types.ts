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
export interface DeploymentConfig {
  mostDeployParams: Omit<DeployParamsStruct, "securityCouncils" | "l1TimelockMinDelay">;
  securityCouncils: SecurityCouncilAndChainID[];
  chainIDs: ChainIDs
}

export interface ChainIDToConnectedSigner {
  [key: number]: Signer;
}