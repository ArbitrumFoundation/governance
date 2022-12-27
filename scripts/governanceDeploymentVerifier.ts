import { verifyDeployment } from "./verifiers";

async function main() {
  console.log("Start verification process...");
  await verifyDeployment();
}

main().then(() => console.log("Done."));
