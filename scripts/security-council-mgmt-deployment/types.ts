import { DeployParamsStruct } from "../../typechain-types/src/security-council-mgmt/factories/L2SecurityCouncilMgmtFactory";
import { Signer } from "ethers";
import { JsonRpcProvider } from "@ethersproject/providers";

export interface SecurityCouncilAndConnectedSigner {
  securityCouncilAddress: string;
  connectedSigner: Signer;
}
export interface DeploymentConfig {
  mostDeployParams: Omit<DeployParamsStruct, "securityCouncils" | "l1TimelockMinDelay">;
  securityCouncils: SecurityCouncilAndConnectedSigner[];
  connectedGovChainSigner: Signer;
  l1Provider: JsonRpcProvider;
}
