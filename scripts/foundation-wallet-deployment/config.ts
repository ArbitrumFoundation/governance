import { DeployedContracts } from "../../src-ts/types";

import fs from 'fs'

const goerliDeployedContracts = JSON.parse(
  fs.readFileSync("./files/goerli/deployedContracts.json").toString()
) as DeployedContracts;
const mainnetDeployedContracts = JSON.parse(
  fs.readFileSync("./files/mainnet/deployedContracts.json").toString()
) as DeployedContracts;

interface FoundationWalletDeploymentConfig {
  beneficiary: string;
  startTimestamp: number;
  vestingPeriodInSeconds: number;
  l2ArbitrumGovernor: string;
  l2GovProxyAdmin: string;
}

interface ChainIDToConfig {
  [key: number]: FoundationWalletDeploymentConfig;
}

const secondsInADay = 60 * 60 * 24;

const secondsInFourYears = secondsInADay * (365 * 4 + 1); // Days in 4 years, includes 1 day for leap day

const chainIDToConfig: ChainIDToConfig = {
  42161: {
    beneficiary: "", // TODO
    startTimestamp: 0, // TODO
    vestingPeriodInSeconds: secondsInFourYears, 
    l2ArbitrumGovernor: mainnetDeployedContracts.l2CoreGoverner,
    l2GovProxyAdmin: mainnetDeployedContracts.l2ProxyAdmin,
  },
  421613: {
    beneficiary: "", // TODO
    startTimestamp: 0, // TODO
    vestingPeriodInSeconds: 0, // TODO
    l2ArbitrumGovernor: goerliDeployedContracts.l2CoreGoverner,
    l2GovProxyAdmin: goerliDeployedContracts.l2ProxyAdmin,
  },
};

export const getFoundationWalletDeploymentConfig = (
  chainID: number
): FoundationWalletDeploymentConfig => {
  const config = chainIDToConfig[chainID];
  if (!config) throw new Error(`ChainID ${chainID} not configged`);
  return config;
};

interface DeployedWallets {
  [key: number]: string;
}
export const deployedWallets: DeployedWallets = {
  42161: "",
  421613: "",
};
