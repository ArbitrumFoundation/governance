import yargs from "yargs";
import { deploySecurityCouncilMgmtContracts } from "./deployContracts";
import { getMainnetConfig } from "./configs/mainnet";
import { getGoerliConfig } from "./configs/arbgoerli";

/**
 * To run:
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
 * yarn deploy:sc-mgmt --network mainnet | arb-goerli
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
  const config = await (async () => {
    switch (options.network) {
      case "mainnet":
        return getMainnetConfig();
        // TODO
        return getGoerliConfig();
      default:
        throw new Error(`Unsupported network: ${options.network}`);
    }
  })();
  const deployment = await deploySecurityCouncilMgmtContracts(config);
  console.log(deployment);
  //   TODO: save to JSON file?
  return deployment;
};

main().then(() => {
  console.log("Deployment done");
});
