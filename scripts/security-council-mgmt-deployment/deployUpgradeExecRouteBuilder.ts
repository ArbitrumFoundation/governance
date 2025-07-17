import { JsonRpcProvider } from "@ethersproject/providers";
import { ethers, Wallet } from "ethers";
import { UpgradeExecRouteBuilder__factory } from "../../typechain-types";
import * as upgradeExecRouteBuilderParam from "./upgradeExecRouteBuilderParam";

async function deployRouteBuilder() {
  const signer = new Wallet(process.env.PRIVATE_KEY!, new JsonRpcProvider(process.env.ARB_URL!));

  const newRouteBuilder = await new UpgradeExecRouteBuilder__factory(signer).deploy(
    upgradeExecRouteBuilderParam[0],
    upgradeExecRouteBuilderParam[1],
    upgradeExecRouteBuilderParam[2]
  )

  await newRouteBuilder.deployed()
  console.log("UpgradeExecRouteBuilder deployed to:", newRouteBuilder.address);
}

deployRouteBuilder()