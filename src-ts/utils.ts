import { DeployedContracts } from "./types";
import fs from "fs";

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
