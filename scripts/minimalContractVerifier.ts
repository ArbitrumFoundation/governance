import { AbiCoder } from "@ethersproject/abi";
import { ContractFactory } from "ethers";
import { exec } from "child_process";

export type ContractVerificationConfig = {
  factory: ContractFactory,
  contractName: string,
  chainId: number,
  address: string,
  constructorArgs: any[],
  foundryProfile: string,
  etherscanApiKey: string,
};

export async function verifyContracts(configs: ContractVerificationConfig[], delay: number = 1000) {
  for (const config of configs) {
    console.log(`Verifying ${config.address} (${config.contractName}) on chain ${config.chainId}...`);
    if (configs.length > 1) {
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
    await verifyContract(config);
  }
}

export function verifyContract(config: ContractVerificationConfig) {
  const encodedConstructorArgs = new AbiCoder().encode(config.factory.interface.deploy.inputs, config.constructorArgs);
  let command = `FOUNDRY_PROFILE=${config.foundryProfile} forge verify-contract --watch --chain-id ${config.chainId} --etherscan-api-key ${config.etherscanApiKey}`;
  
  if (config.constructorArgs.length > 0) {
    command += ` --constructor-args ${encodedConstructorArgs}`;
  }

  command += ` ${config.address} ${config.contractName}`;

  return new Promise((resolve, reject) => {
    exec(command, (err: Error | null, stdout: string, stderr: string) => {
      if (err) {
        reject([err, stderr]);
      }
      else {
        // could also extract the GUID from stdout and return it instead
        resolve(stdout)
      }
    });
  });
}

// function extractGuid(stdout: string) {
//   return stdout.split("\n").find((line) => line.trim().startsWith("GUID:"))?.split("GUID:")[1].trim().replace('`', '').replace('`', '');
// }