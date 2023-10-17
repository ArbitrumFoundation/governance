import yargs from "yargs";
import mainnetConfig from "./configs/mainnet";
import goerliConfig from "./configs/arbgoerli";
import { deployContracts } from "./deployContracts";

import {promises as fs} from "fs";

/**
 * To run:
 *
 * set params in configs/ file
 * 
 * Set the following env vars:
 * ARB_KEY (pk for funded address on governance chain)
 * ETH_KEY (pk for funding address on l1)
 * ARB_URL (gov chain RPC URL)
 * ETH_ULL (l1 RPC URL)
 *
 * For mainnet only:
 * NOVA_KEY
 * NOVA_URL
 *
 * run:
 * yarn deploy:sc-mgmt --network mainnet | goerli
 *
 */
const options = yargs(process.argv.slice(2))
  .options({
    network: { type: "string", demandOption: true },
  })
  .parseSync() as {
  network: string;
};

const main = async () => {
  let config;
  switch (options.network) {
    case "mainnet":
      config = mainnetConfig;
      break;
    case "goerli":
      config = goerliConfig;
      break;
    default:
      throw new Error(`Unsupported network: ${options.network}`);
  }

  const deployment = await deployContracts(config);

  await fs.writeFile(`./files/${options.network}/scmDeployment.json`, JSON.stringify(deployment, null, 2));

  return deployment;
};

main().then(() => {
  console.log("Deployment done");
});
