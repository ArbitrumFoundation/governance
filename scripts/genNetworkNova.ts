import { ethers, Signer } from "ethers";
import { getSigner, getCustomNetworks } from "../test-ts/testSetup";
import * as fs from "fs";
import { L2Network } from "@arbitrum/sdk";
import { deployErc20AndInit } from "../test-ts/deployBridge";

/**
 * Script deploys L1-Nova bridge contract pairs to local network.
 * Deployed contracts' addresses are stored to 'localNetworkNova.json'
 */
async function main() {
  const config = {
    novaUrl: process.env["NOVA_URL"] as string,
    ethUrl: process.env["ETH_URL"] as string,
    novaKey: process.env["NOVA_KEY"] as string,
    ethKey: process.env["ETH_KEY"] as string,
  };

  const ethProvider = new ethers.providers.JsonRpcProvider(config.ethUrl);
  const novaProvider = new ethers.providers.JsonRpcProvider(config.novaUrl);

  const ethDeployer = getSigner(ethProvider, config.ethKey);
  const novaDeployer = getSigner(novaProvider, config.novaKey);

  const { l1Network, l2Network } = await setupNova(
    ethDeployer,
    novaDeployer,
    config.ethUrl,
    config.novaUrl
  );

  fs.writeFileSync("localNetworkNova.json", JSON.stringify({ l1Network, l2Network }, null, 2));
  console.log("localNetworkNova.json updated");
}

const setupNova = async (
  l1Deployer: Signer,
  novaDeployer: Signer,
  l1Url: string,
  novaUrl: string
) => {
  const { l1Network, l2Network: coreL2Network } = await getCustomNetworks(l1Url, novaUrl);

  const { l1: l1Contracts, l2: l2Contracts } = await deployErc20AndInit(
    l1Deployer,
    novaDeployer,
    coreL2Network.ethBridge.inbox
  );
  const l2Network: L2Network = {
    ...coreL2Network,
    tokenBridge: {
      l1CustomGateway: l1Contracts.customGateway.address,
      l1ERC20Gateway: l1Contracts.standardGateway.address,
      l1GatewayRouter: l1Contracts.router.address,
      l1MultiCall: l1Contracts.multicall.address,
      l1ProxyAdmin: l1Contracts.proxyAdmin.address,
      l1Weth: l1Contracts.weth.address,
      l1WethGateway: l1Contracts.wethGateway.address,

      l2CustomGateway: l2Contracts.customGateway.address,
      l2ERC20Gateway: l2Contracts.standardGateway.address,
      l2GatewayRouter: l2Contracts.router.address,
      l2Multicall: l2Contracts.multicall.address,
      l2ProxyAdmin: l2Contracts.proxyAdmin.address,
      l2Weth: l2Contracts.weth.address,
      l2WethGateway: l2Contracts.wethGateway.address,
    },
  };

  return {
    l1Network,
    l2Network,
  };
};

main()
  .then(() => console.log("Done."))
  .catch(console.error);
