import { JsonRpcProvider } from "@ethersproject/providers";
import { promises as fs } from "fs";
import { assertDefined } from "../../security-council-mgmt-deployment/utils"; // todo: move this somewhere else
import { SecurityCouncilManagementDeploymentResult } from "../../security-council-mgmt-deployment/types";
import { buildProposal } from "../buildProposal";

async function main() {
  const provider = new JsonRpcProvider(assertDefined(process.env.ARB_URL, "ARB_URL is undefined"));

  const chainId = (await provider.getNetwork()).chainId;

  let scmDeploymentPath: string;
  if (chainId === 42161) {
    scmDeploymentPath = "files/mainnet/scmDeployment.json";
  } else if (chainId === 421613) {
    scmDeploymentPath = "files/goerli/scmDeployment.json";
  } else {
    throw new Error(`Unknown chainId ${chainId}`);
  }

  const scmDeployment = JSON.parse((await fs.readFile(scmDeploymentPath)).toString()) as SecurityCouncilManagementDeploymentResult;
  const actions = scmDeployment.activationActionContracts;

  const chainIds = Object.keys(actions).map(k => parseInt(k));
  const actionAddresses = chainIds.map((chainId) => actions[chainId]);

  const proposal = await buildProposal(
    "TODO: add description",
    provider,
    scmDeployment.upgradeExecRouteBuilder,
    chainIds,
    actionAddresses,
  );

  const path = `${__dirname}/data/${chainId}-AIPX-data.json`;
  await fs.mkdir(`${__dirname}/data`, { recursive: true });
  await fs.writeFile(path, JSON.stringify(proposal, null, 2));
  console.log("Wrote proposal data to", path);
  console.log(proposal);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});