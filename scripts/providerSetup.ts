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

import { JsonRpcProvider, Provider } from "@ethersproject/providers";
import { Wallet } from "@ethersproject/wallet";
import dotenv from "dotenv";
import { Signer } from "ethers";
import { ArbSdkError } from "@arbitrum/sdk/dist/lib/dataEntities/errors";
import { getProvidersAndSetupNetworks } from "../test-ts/testSetup";
import path from "path";
import { DeployerConfig, loadDeployerConfig } from "./deployerConfig";
import { getL2Network, L2Network } from "@arbitrum/sdk";
import { testSetup } from "../test-ts/testSetup";

dotenv.config();

const ETH_CHAIN_ID = 1;
const ARBITRUM_ONE_CHAIN_ID = 42161;
const ARBITRUM_NOVA_CHAIN_ID = 42170;

// dotenv config used in case of deploying to production
// in case of local env testing, config is extracted in `testSetup()`
export const config = {
  isLocalDeployment: process.env["DEPLOY_TO_LOCAL_ENVIRONMENT"] as string,
  ethRpc: process.env["ETH_URL"] as string,
  arbRpc: process.env["ARB_URL"] as string,
  novaRpc: process.env["NOVA_URL"] as string,
  ethDeployerKey: process.env["ETH_KEY"] as string,
  arbDeployerKey: process.env["ARB_KEY"] as string,
  novaDeployerKey: process.env["NOVA_KEY"] as string,
  deployerConfigFileName: process.env["DEPLOYER_FILE"] as string,
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
export const getDeployersAndConfig = async (): Promise<{
  ethDeployer: Signer;
  arbDeployer: Signer;
  novaDeployer: Signer;
  deployerConfig: DeployerConfig;
  arbNetwork: L2Network;
  novaNetwork: L2Network;
}> => {
  if (config.isLocalDeployment === "true") {
    // setup local test environment
    const {
      l2Provider,
      l1Provider,
      l2Network: arbNetwork,
    } = await getProvidersAndSetupNetworks({
      l1Url: config.ethRpc,
      l2Url: config.arbRpc,
      networkFilename: "localNetwork.json",
    });

    const { l2Provider: novaProvider, l2Network: novaNetwork } = await getProvidersAndSetupNetworks(
      {
        l1Url: config.ethRpc,
        l2Url: config.novaRpc,
        networkFilename: "localNetworkNova.json",
      }
    );

    const l1Deployer = getSigner(l1Provider, config.ethDeployerKey);
    const l2Deployer = getSigner(l2Provider, config.arbDeployerKey);
    const novaDeployer = getSigner(novaProvider, config.novaDeployerKey);

    // check that production chains are not mistakenly used in local env
    if (l1Deployer.provider) {
      const l1ChainId = (await l1Deployer.provider.getNetwork()).chainId;
      if (l1ChainId == ETH_CHAIN_ID) {
        throw new Error("Production chain ID used in test env for L1");
      }
    }
    if (l2Deployer.provider) {
      const l2ChainId = (await l2Deployer.provider.getNetwork()).chainId;
      if (l2ChainId == ARBITRUM_ONE_CHAIN_ID) {
        throw new Error("Production chain ID used in test env for L2");
      }
    }
    if (novaDeployer.provider) {
      const novaChainId = (await novaDeployer.provider.getNetwork()).chainId;
      if (novaChainId == ARBITRUM_NOVA_CHAIN_ID) {
        throw new Error("Production chain ID used in test env for Nova");
      }
    }

    const testDeployerConfigName = path.join(__dirname, "testConfig.json");
    const deployerConfig = await loadDeployerConfig(testDeployerConfigName);

    return {
      ethDeployer: l1Deployer,
      arbDeployer: l2Deployer,
      novaDeployer: novaDeployer,
      deployerConfig,
      arbNetwork,
      novaNetwork,
    };
  } else {
    // deploying to production
    const ethProvider = new JsonRpcProvider(config.ethRpc);
    const arbProvider = new JsonRpcProvider(config.arbRpc);
    const novaProvider = new JsonRpcProvider(config.novaRpc);

    // check that production chain IDs are used in production mode
    const ethChainId = (await ethProvider.getNetwork()).chainId;
    if (ethChainId != ETH_CHAIN_ID) {
      throw new Error("Production chain ID should be used in production mode for L1");
    }
    const arbChainId = (await arbProvider.getNetwork()).chainId;
    if (arbChainId != ARBITRUM_ONE_CHAIN_ID) {
      throw new Error("Production chain ID should be used in production mode for L2");
    }
    const novaChainId = (await novaProvider.getNetwork()).chainId;
    if (novaChainId != ARBITRUM_NOVA_CHAIN_ID) {
      throw new Error("Production chain ID should be used in production mode for Nova");
    }

    const ethDeployer = getSigner(ethProvider, config.ethDeployerKey);
    const arbDeployer = getSigner(arbProvider, config.arbDeployerKey);
    const novaDeployer = getSigner(novaProvider, config.novaDeployerKey);

    const testDeployerConfigName = path.join(__dirname, config.deployerConfigFileName);
    const deployerConfig = await loadDeployerConfig(testDeployerConfigName);

    const arbNetwork = await getL2Network(arbProvider);
    const novaNetwork = await getL2Network(novaProvider);

    return {
      ethDeployer,
      arbDeployer,
      novaDeployer,
      deployerConfig,
      arbNetwork,
      novaNetwork,
    };
  }
};

/**
 * Fetch providers for mainnet, ArbitrumOne and Nova.
 * RPCs endpoints are loaded from env vars:
 *  - ETH_URL, ARB_URL, NOVA_URL for test deployment in local env (DEPLOY_TO_LOCAL_ENVIRONMENT = 'true')
 *  - MAINNET_RPC, ARB_ONE_RPC, NOVA_RPC for production deployment (DEPLOY_TO_LOCAL_ENVIRONMENT = 'false')
 *
 * @returns
 */
export const getProviders = async (): Promise<{
  ethProvider: Provider;
  arbProvider: Provider;
  novaProvider: Provider;
  deployerConfig: DeployerConfig;
  arbNetwork: L2Network;
  novaNetwork: L2Network;
}> => {
  const { arbDeployer, deployerConfig, ethDeployer, novaDeployer, arbNetwork, novaNetwork } =
    await getDeployersAndConfig();

  return {
    ethProvider: ethDeployer.provider!,
    arbProvider: arbDeployer.provider!,
    novaProvider: novaDeployer.provider!,
    deployerConfig,
    arbNetwork,
    novaNetwork,
  };
};

/**
 * Get addresses for every deployer account.
 * @returns
 */
export const getDeployerAddresses = async (): Promise<{
  ethDeployerAddress: string;
  arbDeployerAddress: string;
  novaDeployerAddress: string;
}> => {
  const { ethDeployer, arbDeployer, novaDeployer } = await getDeployersAndConfig();
  const ethDeployerAddress = await ethDeployer.getAddress();
  const arbDeployerAddress = await arbDeployer.getAddress();
  const novaDeployerAddress = await novaDeployer.getAddress();

  return {
    ethDeployerAddress,
    arbDeployerAddress,
    novaDeployerAddress,
  };
};

/**
 * Governance will be deployed to Nova only if env var 'DEPLOY_GOVERNANCE_TO_NOVA' is set to 'true'.
 *
 * @returns
 */
export function isDeployingToNova(): boolean {
  const deployToNova = process.env["DEPLOY_GOVERNANCE_TO_NOVA"] as string;
  return deployToNova === "true";
}
