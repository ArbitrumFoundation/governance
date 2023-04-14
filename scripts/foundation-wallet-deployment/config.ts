interface FoundationWalletDeploymentConfig {
  beneficiary: string;
  startTimestamp: number;
  durationSeconds: number;
  l2ArbitrumGovernor: string;
  l2UpgradeExecutor: string;
  l2GovProxyAdmin: string;
}

interface ChainIDToConfig {
  [key: number]: FoundationWalletDeploymentConfig;
}

const secondsInADay = 60 * 60 * 24;

const chainIDToConfig: ChainIDToConfig = {
  42161: {
    beneficiary: "",
    startTimestamp: 0,
    durationSeconds: secondsInADay * (365 * 4 + 1), // Days in 4 years, includes 1 day for leap day
    l2ArbitrumGovernor: "0xf07DeD9dC292157749B6Fd268E37DF6EA38395B9",
    l2UpgradeExecutor: "0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827",
    l2GovProxyAdmin: "0xdb216562328215E010F819B5aBe947bad4ca961e",
  },
  421613: {
    beneficiary: "",
    startTimestamp: 0,
    durationSeconds: 0,
    l2ArbitrumGovernor: "0xa584d185244DCbCa8A98dBdB4e550a5De3A64c81",
    l2UpgradeExecutor: "0x67AcB531A05160A81dCD03079347f264c4FA2da3",
    l2GovProxyAdmin: "0x8CfA7Dc239B15E2b4cA6E4B4F4d044f49d5558d4",
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
