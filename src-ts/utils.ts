import { DeployedContracts } from "./types";
import * as fs from "fs";
import {
  L2ArbitrumGovernor__factory,
  SecurityCouncilNomineeElectionGovernor__factory,
} from "../typechain-types";
import { Contract } from "ethers";
import { Provider } from "@ethersproject/providers";

export const wait = async (ms: number) => new Promise((res) => setTimeout(res, ms));

export const importDeployedContracts = (path: string): DeployedContracts => {
  const res = JSON.parse(fs.readFileSync(path).toString());
  if (isDeployedContracts(res)) {
    return res;
  } else {
    throw new Error("Invalid deployed contracts");
  }
};

const isDeployedContracts = (obj: any): obj is DeployedContracts => {
  return obj.l1Timelock !== undefined && obj.l2Executor !== undefined;
};

export const hasTimelock = async (govAddress: string, provider: Provider) => {
  try {
    await L2ArbitrumGovernor__factory.connect(govAddress, provider).timelock();
    return true;
  } catch (e) {
    return false;
  }
};

export const hasVettingPeriod = async (govAddress: string, provider: Provider) => {
  try {
    await SecurityCouncilNomineeElectionGovernor__factory.connect(
      govAddress,
      provider
    ).nomineeVetter();
    return true;
  } catch (e) {
    return false;
  }
};

export const getL1BlockNumberFromL2 = async (provider: Provider) => {
  const multicallAddress = await (async () => {
    switch ((await provider.getNetwork()).chainId) {
      case 42161:
        return "0x7eCfBaa8742fDf5756DAC92fbc8b90a19b8815bF";
      case 421613:
        return "0x108B25170319f38DbED14cA9716C54E5D1FF4623";
      default:
        throw new Error("Multicall address not supported");
    }
  })();
  const multicall = new Contract(
    multicallAddress,
    ["function getL1BlockNumber() view returns (uint256)"],
    provider
  );
  return multicall.getL1BlockNumber();
};
