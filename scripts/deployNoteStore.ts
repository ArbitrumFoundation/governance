import { JsonRpcProvider } from "@ethersproject/providers";
import { Wallet } from "ethers";
import { randomBytes } from "ethers/lib/utils";
import { NoteStore__factory, TestUpgrade__factory } from "../typechain-types";
import { ContractVerifier } from "./contractVerifier";

async function main() {
  const deployRpc = process.env["DEPLOY_RPC"] as string;
  if (deployRpc == undefined) {
    throw new Error("Env var 'DEPLOY_RPC' not set");
  }
  const rpc = new JsonRpcProvider(deployRpc);
  const deployKey = process.env["DEPLOY_KEY"] as string;
  if (deployKey == undefined) {
    throw new Error("Env var 'DEPLOY_KEY' not set");
  }
  const wallet = new Wallet(deployKey).connect(rpc);

  const apiKey = process.env["VERIFY_API_KEY"] as string;
  if (apiKey == undefined) {
    throw new Error("Env var 'VERIFY_API_KEY' not set");
  }

  const noteStore = await new NoteStore__factory(wallet).deploy();
  await noteStore.deployed();
  const testUpgrade = await new TestUpgrade__factory(wallet).deploy();
  await testUpgrade.deployed();

  const testNote = "0x" + Buffer.from(randomBytes(32)).toString("hex");
  const upgradeData = testUpgrade.interface.encodeFunctionData("upgrade", [
    noteStore.address,
    testNote,
  ]);

  console.log(
    JSON.stringify(
      {
        noteStoreAddr: noteStore.address,
        testUpgradeAddr: testUpgrade.address,
        testNote: testNote,
        upgradeData: upgradeData,
      },
      null,
      2
    )
  );

  const verifier = new ContractVerifier((await rpc.getNetwork()).chainId, apiKey, {});
  await verifier.verifyWithAddress("noteStore", noteStore.address);
  await verifier.verifyWithAddress("testUpgrade", testUpgrade.address);
}

main().then(() => console.log("Done."));
