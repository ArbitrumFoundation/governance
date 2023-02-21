import { envVars, getDeployersAndConfig, getProviders, isDeployingToNova } from "./providerSetup";
import { getProxyOwner } from "./testUtils";
import { ethers } from "ethers";
import fs from "fs";
import { L2Network } from "@arbitrum/sdk";
import { ArbOwner__factory } from "@arbitrum/sdk/dist/lib/abi/factories/ArbOwner__factory";
import {
  BeaconProxyFactory__factory,
  L2ERC20Gateway__factory,
  UpgradeableBeacon__factory,
} from "../token-bridge-contracts/build/types";
import { Provider } from "@ethersproject/providers";

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
  const { l1ProtocolOwnerTXs, l1TokenBridgeOwnerTXs, l2TXs } = await generateAssetTransferTXs(
    arbNetwork,
    ethProvider,
    arbProvider,
    l1Executor,
    arbExecutor
  );

  // transfer protocol
  const l1ArbProtocolBatch: GnosisBatch = getGnosisBatch(
    arbNetwork.partnerChainID,
    l1ProtocolOwnerTXs
  );
  fs.writeFileSync(envVars.l1ArbProtocolTransferTXsLocation, JSON.stringify(l1ArbProtocolBatch));
  console.log("Arb L1 protocol transfer TXs file:", envVars.l1ArbProtocolTransferTXsLocation);

  // transfer token bridge
  const l1ArbTokenBridgeBatch: GnosisBatch = getGnosisBatch(
    arbNetwork.partnerChainID,
    l1TokenBridgeOwnerTXs
  );
  fs.writeFileSync(
    envVars.l1ArbTokenBridgeTransferTXsLocation,
    JSON.stringify(l1ArbTokenBridgeBatch)
  );
  console.log(
    "Arb L1 token bridge transfer TXs file:",
    envVars.l1ArbTokenBridgeTransferTXsLocation
  );

  // transfer L2
  const arbAssetsBatch: GnosisBatch = getGnosisBatch(arbNetwork.chainID, l2TXs);
  fs.writeFileSync(envVars.arbTransferAssetsTXsLocation, JSON.stringify(arbAssetsBatch));
  console.log("Arb L2 TXs file:", envVars.arbTransferAssetsTXsLocation);

  ///// Nova
  if (isDeployingToNova()) {
    // TXs to transfer ownership of Nova assets
    const novaExecutor = contractAddresses["novaUpgradeExecutorProxy"];
    const { l1ProtocolOwnerTXs, l1TokenBridgeOwnerTXs, l2TXs } = await generateAssetTransferTXs(
      novaNetwork,
      ethProvider,
      novaProvider,
      l1Executor,
      novaExecutor
    );

    // transfer protocol
    const l1NovaProtocolBatch: GnosisBatch = getGnosisBatch(
      novaNetwork.partnerChainID,
      l1ProtocolOwnerTXs
    );
    fs.writeFileSync(
      envVars.l1NovaProtocolTransferTXsLocation,
      JSON.stringify(l1NovaProtocolBatch)
    );
    console.log("Nova L1 protocol transfer TXs file:", envVars.l1NovaProtocolTransferTXsLocation);

    // transfer token bridge
    const l1NovaTokenBridgeBatch: GnosisBatch = getGnosisBatch(
      novaNetwork.partnerChainID,
      l1TokenBridgeOwnerTXs
    );
    fs.writeFileSync(
      envVars.l1NovaTokenBridgeTransferTXsLocation,
      JSON.stringify(l1NovaTokenBridgeBatch)
    );
    console.log(
      "Nova L1 token bridge transfer TXs file:",
      envVars.l1NovaTokenBridgeTransferTXsLocation
    );

    // transfer L2
    const novaAssetsBatch: GnosisBatch = getGnosisBatch(novaNetwork.chainID, l2TXs);
    fs.writeFileSync(envVars.novaTransferAssetsTXsLocation, JSON.stringify(novaAssetsBatch));
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
  /// L1 protocol owner TXs
  let l1ProtocolOwnerTXs: GnosisTX[] = new Array();
  l1ProtocolOwnerTXs.push(await generateRollupSetOwnerTX(l2Network.ethBridge.rollup, l1Executor));
  l1ProtocolOwnerTXs.push(
    await generateProxyAdminTransferOwnershipTX(
      await getProxyOwner(l2Network.ethBridge.inbox, l1Provider),
      l1Executor
    )
  );

  /// L1 token bridge owner TXs
  let l1TokenBridgeOwnerTXs: GnosisTX[] = new Array();
  l1TokenBridgeOwnerTXs.push(
    await generateProxyAdminTransferOwnershipTX(
      await getProxyOwner(l2Network.tokenBridge.l1GatewayRouter, l1Provider),
      l1Executor
    )
  );
  l1TokenBridgeOwnerTXs.push(
    await generateRouterSetOwnerTX(l2Network.tokenBridge.l1GatewayRouter, l1Executor)
  );
  l1TokenBridgeOwnerTXs.push(
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
  l2TXs.push(
    await generateBeaconTransferOwnershipTX(
      l2Network.tokenBridge.l2ERC20Gateway,
      l2Executor,
      l2Provider
    )
  );
  l2TXs.push(...(await getChainOwnerTransferTXs(l2Provider, l2Executor)));

  return {
    l1ProtocolOwnerTXs,
    l1TokenBridgeOwnerTXs,
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

/**
 * Set beacon's owner
 */
async function generateBeaconTransferOwnershipTX(
  l2ERC20GatewayAddress: string,
  executorAddress: string,
  l2Provider: Provider
): Promise<Promise<GnosisTX>> {
  const l2Erc20Gw = L2ERC20Gateway__factory.connect(l2ERC20GatewayAddress, l2Provider);
  const beaconProxyFactory = BeaconProxyFactory__factory.connect(
    await l2Erc20Gw.beaconProxyFactory(),
    l2Provider
  );
  const beacon = UpgradeableBeacon__factory.connect(await beaconProxyFactory.beacon(), l2Provider);

  return {
    to: beacon.address,
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
