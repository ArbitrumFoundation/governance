import { JsonRpcProvider } from "@ethersproject/providers";
import { promises as fs } from "fs";
import { assertDefined } from "../../security-council-mgmt-deployment/utils"; // todo: move this somewhere else
import { SecurityCouncilManagementDeploymentResult } from "../../security-council-mgmt-deployment/types";
import { buildProposal } from "../buildProposal";
import dotenv from "dotenv";
dotenv.config();

const description = `SC non emergency action`;

async function main() {
  const provider = new JsonRpcProvider(assertDefined(process.env.ARB_URL, "ARB_URL is undefined"));

  const chainId = (await provider.getNetwork()).chainId;

  let scmDeploymentPath: string;
  if (chainId === 42161) {
    scmDeploymentPath = "files/mainnet/scmDeployment.json";
  } else {
    throw new Error(`Unknown chainId ${chainId}`);
  }

  const scmDeployment = JSON.parse(
    (await fs.readFile(scmDeploymentPath)).toString()
  ) as SecurityCouncilManagementDeploymentResult;

  // the keyset added in that action can be verified using the instructions in
  // https://forum.arbitrum.foundation/t/non-emergency-security-council-action-update-arbitrum-nova-dac-keyset/19379
  const addNovaKeysetAction = "0xDef5CfE3246882BC7f65F9346a8b974BA27D3F4E"

  const chainIds = [1];
  const actionAddresses = [addNovaKeysetAction];

  const proposal = await buildProposal(
    provider,
    scmDeployment.upgradeExecRouteBuilder,
    chainIds,
    actionAddresses
  );

  const path = `${__dirname}/data/${chainId}-dac-update-data.json`;
  await fs.mkdir(`${__dirname}/data`, { recursive: true });
  await fs.writeFile(path, JSON.stringify(proposal, null, 2));
  console.log("Wrote proposal data to", path);
  console.log(proposal);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
