// JSON file which contains all the deployed contract addresses
const DEPLOYED_CONTRACTS_FILE_NAME = "deployedContracts.json";

export const verifyDeployment = async () => {
  const contracts = require("../" + DEPLOYED_CONTRACTS_FILE_NAME);
  console.log(contracts);
};
s
async function main() {
  console.log("Start verification process...");
  await verifyDeployment();
}

main()
  .then(() => console.log("Done."))
  .catch(console.error);
