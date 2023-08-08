import * as fs from "fs";
import { DeployedContracts } from "../../src-ts/types";

export function blocks(num: number, unit: 'hours' | 'days', blockTime = 12) {
  let seconds;
  switch (unit) {
    case 'hours':
      seconds = num * 60 * 60;
      break;
    case 'days':
      seconds = num * 24 * 60 * 60;
      break;
    default:
      throw new Error(`invalid unit: ${unit}`);
  }
  return Math.floor(seconds / blockTime);
}

export function assertDefined<T>(val: T | undefined, msg = "value is undefined"): T {
  if (val === undefined) {
    throw new Error(msg);
  }
  return val;
}

export function readDeployedContracts(path: string) {
  return JSON.parse(
    fs.readFileSync(path).toString()
  ) as DeployedContracts;
}

export function randomNonce() {
  return Math.floor(Math.random() * Number.MAX_SAFE_INTEGER);
}

export function getNamedObjectItems(obj: {[s: string]: unknown} | ArrayLike<unknown>) {
  return Object.entries(obj).reduce((acc, [key, value]) => isNaN(Number(key)) ? {...acc, [key]: value} : acc, {});
}