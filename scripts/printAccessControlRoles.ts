import { JsonRpcProvider } from "@ethersproject/providers";
import dotenv from "dotenv";
import { getCurrentRoles } from "./checkAccessControlRoles";
dotenv.config();

(async () => {
  const ethRpc = new JsonRpcProvider(process.env.ETH_URL);

  const arbOneRpc = new JsonRpcProvider(process.env.ARB_URL);

  const novaRPC = new JsonRpcProvider(process.env.NOVA_URL);

  await getCurrentRoles(arbOneRpc, "0x34d45e99f7D8c45ed05B5cA72D54bbD1fb3F98f0", "L2 Core Timelock");
  await getCurrentRoles(arbOneRpc, "0xD509E5f5aEe2A205F554f36E8a7d56094494eDFC", "Security Council Manager");
  await getCurrentRoles(arbOneRpc, "0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827", "Arb1 Upgrade Executor");

  await getCurrentRoles(ethRpc, "0xE6841D92B0C345144506576eC13ECf5103aC7f49", "L1 Timelock");
  await getCurrentRoles(ethRpc, "0x3ffFbAdAF827559da092217e474760E2b2c3CeDd", "L1 Upgrade Executor");

  await getCurrentRoles(novaRPC, "0x86a02dD71363c440b21F4c0E5B2Ad01Ffe1A7482", "Nova Upgrade Executor");
})();
