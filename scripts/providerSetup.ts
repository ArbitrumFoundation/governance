/*
 * Copyright 2021, Offchain Labs, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
/* eslint-env node */
"use strict";

import { JsonRpcProvider } from "@ethersproject/providers";
import { Wallet } from "@ethersproject/wallet";
import dotenv from "dotenv";
import { Signer } from "ethers";
import { ArbSdkError } from "@arbitrum/sdk/dist/lib/dataEntities/errors";
import { fundL2, testSetup } from "../test-ts/testSetup";
import { parseEther } from "ethers/lib/utils";

dotenv.config();

// dotenv config used in case of deploying to production
// in case of local env testing, config is extracted in `testSetup()`
export const config = {
  isLocalDeployment: process.env["DEPLOY_TO_LOCAL_ENVIRONMENT"] as string,
  ethRpc: process.env["MAINNET_RPC"] as string,
  arbRpc: process.env["ARB_ONE_RPC"] as string,
  ethDeployerKey: process.env["ETH_DEPLOYER_KEY"] as string,
  arbDeployerKey: process.env["ARB_DEPLOYER_KEY"] as string,
  arbInitialSupplyRecipientKey: process.env["ARB_INITIAL_SUPPLY_RECIPIENT_KEY"] as string,
};

export const getSigner = (provider: JsonRpcProvider, key?: string) => {
  if (!key && !provider) throw new ArbSdkError("Provide at least one of key or provider.");
  if (key) return new Wallet(key).connect(provider);
  else return provider.getSigner(0);
};

/**
 * Fetch deployers and token receiver.
 * If script is used in local testing environment it uses `testSetup` to set up testing environment.
 * @returns
 */
export const getDeployers = async (): Promise<{
  ethDeployer: Signer;
  arbDeployer: Signer;
  arbInitialSupplyRecipient: Signer;
}> => {
  if (config.isLocalDeployment === "true") {
    // setup local test environment
    const { l2Deployer, l2Signer, l1Deployer } = await testSetup();
    await fundL2(l2Signer, parseEther("1"));
    return {
      ethDeployer: l1Deployer,
      arbDeployer: l2Deployer,
      arbInitialSupplyRecipient: l2Signer,
    };
  } else {
    // deploying to production
    const ethProvider = new JsonRpcProvider(config.ethRpc);
    const arbProvider = new JsonRpcProvider(config.arbRpc);

    const ethDeployer = getSigner(ethProvider, config.ethDeployerKey);
    const arbDeployer = getSigner(arbProvider, config.arbDeployerKey);
    const arbInitialSupplyRecipient = getSigner(arbProvider, config.arbInitialSupplyRecipientKey);

    return {
      ethDeployer,
      arbDeployer,
      arbInitialSupplyRecipient,
    };
  }
};
