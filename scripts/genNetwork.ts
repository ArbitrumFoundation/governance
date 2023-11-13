import { Wallet, ethers } from "ethers";
import { setupNetworks, config, getSigner } from "../test-ts/testSetup";
import * as fs from "fs";
import { formatEther, parseEther } from "ethers/lib/utils";

async function main() {
  const ethProvider = new ethers.providers.JsonRpcProvider(config.ethUrl);
  const arbProvider = new ethers.providers.JsonRpcProvider(config.arbUrl);

  const ethDeployer = getSigner(ethProvider, config.ethKey);
  const arbDeployer = getSigner(arbProvider, config.arbKey);
  console.log(
    "arbdeployer",
    await arbDeployer.getAddress(),
    (await arbDeployer.getBalance()).toString(),
    formatEther(await arbDeployer.getBalance())
  );
  const l1mnemonic = "indoor dish desk flag debris potato excuse depart ticket judge file exit";
  for (let index = 0; index < 5; index++) {
    const wal = ethers.Wallet.fromMnemonic(l1mnemonic, "m/44'/60'/0'/0/" + index);
    console.log(wal.address, (await wal.connect(arbProvider).getBalance()).toString());
  }

  const a = new Wallet("b6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659").connect(arbProvider)
  console.log(a.address, (await a.getBalance()).toString());

  const { l1Network, l2Network } = await setupNetworks(
    ethDeployer,
    arbDeployer,
    config.ethUrl,
    config.arbUrl
  );

  fs.writeFileSync("./files/local/network.json", JSON.stringify({ l1Network, l2Network }, null, 2));
  console.log("network.json updated");
}

main().then(() => console.log("Done."));
