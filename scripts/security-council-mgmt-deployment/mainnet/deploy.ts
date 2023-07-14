import { getMainnetConfig } from "./config";
import { deploySecurityCouncilMgmtContracts } from "../deployContracts";

const main = async () => {
  const config = await getMainnetConfig();
  await deploySecurityCouncilMgmtContracts(config);
};

main().then(() => {
  console.log("Deployment done");
});
