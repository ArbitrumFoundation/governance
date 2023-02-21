import { JsonRpcProvider } from "@ethersproject/providers";
import { Wallet } from "ethers";
import { NoteStore__factory, TestUpgrade__factory } from "../typechain-types";
import { randomBytes } from "ethers/lib/utils";

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
}

main().then(() => console.log("Done."));
