import { JsonRpcProvider } from "@ethersproject/providers";
import { ethers, Wallet } from "ethers";
import { UpgradeExecRouteBuilder__factory } from "../../typechain-types";

async function deployRouteBuilder() {
  const signer = new Wallet(process.env.PRIVATE_KEY!, new JsonRpcProvider(process.env.ARB_URL!));

  const newRouteBuilder = await new UpgradeExecRouteBuilder__factory(signer).deploy(
    [
      {
        chainId: 1,
        location: {
          inbox: ethers.constants.AddressZero,
          upgradeExecutor: '0x3ffFbAdAF827559da092217e474760E2b2c3CeDd'
        }
      },
      {
        chainId: 42161,
        location: {
          inbox: '0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f',
          upgradeExecutor: '0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827'
        }
      },
      {
        chainId: 42170,
        location: {
          inbox: '0xc4448b71118c9071Bcb9734A0EAc55D18A153949',
          upgradeExecutor: '0x86a02dD71363c440b21F4c0E5B2Ad01Ffe1A7482'
        }
      }
    ],
    '0xE6841D92B0C345144506576eC13ECf5103aC7f49',
    259200
  )

  await newRouteBuilder.deployed()
  console.log("UpgradeExecRouteBuilder deployed to:", newRouteBuilder.address);
}

deployRouteBuilder()