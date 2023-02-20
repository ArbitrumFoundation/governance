import { envVars, getDeployersAndConfig, getProviders, isDeployingToNova } from "./providerSetup";
import { getProxyOwner } from "./testUtils";
import { ProxyAdmin__factory } from "../typechain-types";
import { RollupAdminLogic__factory } from "@arbitrum/sdk/dist/lib/abi/factories/RollupAdminLogic__factory";
import { ethers, PopulatedTransaction } from "ethers";
import fs from "fs";
import { L2Network } from "@arbitrum/sdk";
import { ArbOwner__factory } from "@arbitrum/sdk/dist/lib/abi/factories/ArbOwner__factory";
import {
  L1CustomGateway__factory,
  L1GatewayRouter__factory,
} from "../token-bridge-contracts/build/types";

const ARB_OWNER_PRECOMPILE = "0x0000000000000000000000000000000000000070";

export type GnosisTX = {
  to: string;
  value: string;
  data: string;
  contractMethod: {
    inputs: {
      internalType: string;
      name: string;
      type: string;
    }[];
    name: string;
    payable: boolean;
  };
  contractInputsValues: {
    value: string;
  };
};

export type GnosisBatch = {
  chainId: string;
  meta: {
    checksum: string;
  };
  transactions: GnosisTX[];
};

/**
 * Generate calldata for all the TXs needed to transfer asset ownership to DAO.
 * Output with TX data is written to JSON files for Arb and Nova.
 *
 */
export const prepareAssetTransferTXs = async () => {
  const { arbNetwork, novaNetwork } = await getDeployersAndConfig();
  const { ethProvider, arbProvider, novaProvider } = await getProviders();

  const contractAddresses = require("../" + envVars.deployedContractsLocation);
  const l1Executor = contractAddresses["l1Executor"];
  const arbExecutor = contractAddresses["l2Executor"];

  // TXs to transfer ownership of ArbOne assets
  const { l1TXs, l2TXs } = await generateAssetTransferTXs(
    arbNetwork,
    ethProvider,
    arbProvider,
    l1Executor,
    arbExecutor
  );

  const l1ArbAssetsTransfer: GnosisBatch = getGnosisBatch(arbNetwork.partnerChainID, l1TXs);
  fs.writeFileSync(envVars.l1ArbTransferAssetsTXsLocation, JSON.stringify(l1ArbAssetsTransfer));
  console.log("Nova L1 TXs file:", envVars.l1ArbTransferAssetsTXsLocation);

  const arbAssetsTransfer: GnosisBatch = getGnosisBatch(arbNetwork.chainID, l2TXs);
  fs.writeFileSync(envVars.arbTransferAssetsTXsLocation, JSON.stringify(arbAssetsTransfer));
  console.log("Nova L1 TXs file:", envVars.arbTransferAssetsTXsLocation);

  if (isDeployingToNova()) {
    // TXs to transfer ownership of Nova assets
    const novaExecutor = contractAddresses["novaUpgradeExecutorProxy"];
    const { l1TXs, l2TXs } = await generateAssetTransferTXs(
      novaNetwork,
      ethProvider,
      novaProvider,
      l1Executor,
      novaExecutor
    );
    const l1NovaAssetsTransfer: GnosisBatch = getGnosisBatch(novaNetwork.partnerChainID, l1TXs);
    fs.writeFileSync(envVars.l1NovaTransferAssetsTXsLocation, JSON.stringify(l1NovaAssetsTransfer));
    console.log("Nova L1 TXs file:", envVars.l1NovaTransferAssetsTXsLocation);

    const novaAssetsTransfer: GnosisBatch = getGnosisBatch(novaNetwork.chainID, l2TXs);
    fs.writeFileSync(envVars.novaTransferAssetsTXsLocation, JSON.stringify(novaAssetsTransfer));
    console.log("Nova L2 TXs file:", envVars.novaTransferAssetsTXsLocation);
  }
};

/**
 * Get TXs in Gnosis Safe's JSON format
 *
 * @param chainId
 * @param txs
 * @returns
 */
function getGnosisBatch(chainId: number, txs: GnosisTX[]): GnosisBatch {
  return {
    chainId: chainId.toString(),
    meta: {
      checksum: "",
    },
    transactions: txs,
  };
}

/**
 * Generate data for 4 ownership transfer TXs:
 * - rollup
 * - protocol L1 proxy admin
 * - token bridge L1 proxy admin
 * - token bridge L2 proxy admin
 *
 * @returns
 */
async function generateAssetTransferTXs(
  l2Network: L2Network,
  l1Provider: ethers.providers.Provider,
  l2Provider: ethers.providers.Provider,
  l1Executor: string,
  l2Executor: string
) {
  /// L1
  let l1TXs: GnosisTX[] = new Array();
  l1TXs.push(await generateRollupSetOwnerTX(l2Network.ethBridge.rollup, l1Executor));
  l1TXs.push(
    await generateProxyAdminTransferOwnershipTX(
      await getProxyOwner(l2Network.ethBridge.inbox, l1Provider),
      l1Executor
    )
  );
  l1TXs.push(
    await generateProxyAdminTransferOwnershipTX(
      await getProxyOwner(l2Network.tokenBridge.l1GatewayRouter, l1Provider),
      l1Executor
    )
  );
  l1TXs.push(await generateRouterSetOwnerTX(l2Network.tokenBridge.l1GatewayRouter, l1Executor));
  l1TXs.push(
    await generateCustomGatewaySetOwnerTX(l2Network.tokenBridge.l1CustomGateway, l1Executor)
  );

  /// L2
  let l2TXs: GnosisTX[] = new Array();
  l2TXs.push(
    await generateProxyAdminTransferOwnershipTX(
      await getProxyOwner(l2Network.tokenBridge.l2GatewayRouter, l2Provider),
      l2Executor
    )
  );
  l2TXs.push(...(await getChainOwnerTransferTXs(l2Provider, l2Executor)));

  return {
    l1TXs,
    l2TXs,
  };
}

/**
 * Generate TXs to set executor as owner and remove old owners from ArbOwner.
 *
 * @param l2Network
 * @param provider
 * @param l2Executor
 * @returns
 */
async function getChainOwnerTransferTXs(
  provider: ethers.providers.Provider,
  l2Executor: string
): Promise<GnosisTX[]> {
  const ownerPrecompile = ArbOwner__factory.connect(ARB_OWNER_PRECOMPILE, provider);

  let txs: GnosisTX[] = [];
  txs.push({
    to: ownerPrecompile.address,
    value: "0",
    data: "",
    contractMethod: {
      inputs: [
        {
          internalType: "address",
          name: "newOwner",
          type: "address",
        },
      ],
      name: "addChainOwner",
      payable: false,
    },
    contractInputsValues: {
      value: l2Executor,
    },
  });

  const oldOwners = await ownerPrecompile.getAllChainOwners();
  for (let oldOwner of oldOwners) {
    // make sure new owner, l2Executor, is not accidentally removed
    if (oldOwner == l2Executor) {
      continue;
    }

    txs.push({
      to: ownerPrecompile.address,
      value: "0",
      data: "",
      contractMethod: {
        inputs: [
          {
            internalType: "address",
            name: "ownerToRemove",
            type: "address",
          },
        ],
        name: "removeChainOwner",
        payable: false,
      },
      contractInputsValues: {
        value: oldOwner,
      },
    });
  }

  return txs;
}

/**
 * Set rollup's owner
 */
async function generateRollupSetOwnerTX(
  rollupAddress: string,
  l1Executor: string
): Promise<GnosisTX> {
  return {
    to: rollupAddress,
    value: "0",
    data: "",
    contractMethod: {
      inputs: [
        {
          internalType: "address",
          name: "newOwner",
          type: "address",
        },
      ],
      name: "setOwner",
      payable: false,
    },
    contractInputsValues: {
      value: l1Executor,
    },
  };
}

/**
 * Set router's owner
 */
async function generateRouterSetOwnerTX(
  gatewayRouterAddress: string,
  l1Executor: string
): Promise<GnosisTX> {
  return {
    to: gatewayRouterAddress,
    value: "0",
    data: "",
    contractMethod: {
      inputs: [
        {
          internalType: "address",
          name: "newOwner",
          type: "address",
        },
      ],
      name: "setOwner",
      payable: false,
    },
    contractInputsValues: {
      value: l1Executor,
    },
  };
}

/**
 * Set custom gateways's owner
 */
async function generateCustomGatewaySetOwnerTX(
  l1CustomGatewayAddress: string,
  l1Executor: string
): Promise<GnosisTX> {
  return {
    to: l1CustomGatewayAddress,
    value: "0",
    data: "",
    contractMethod: {
      inputs: [
        {
          internalType: "address",
          name: "newOwner",
          type: "address",
        },
      ],
      name: "setOwner",
      payable: false,
    },
    contractInputsValues: {
      value: l1Executor,
    },
  };
}

/**
 * Set proxy admin's owner
 */
async function generateProxyAdminTransferOwnershipTX(
  proxyAdminAddress: string,
  executorAddress: string
): Promise<Promise<GnosisTX>> {
  return {
    to: proxyAdminAddress,
    value: "0",
    data: "",
    contractMethod: {
      inputs: [
        {
          internalType: "address",
          name: "newOwner",
          type: "address",
        },
      ],
      name: "transferOwnership",
      payable: false,
    },
    contractInputsValues: {
      value: executorAddress,
    },
  };
}

async function main() {
  await prepareAssetTransferTXs();
}

main().then(() => console.log("Done."));
