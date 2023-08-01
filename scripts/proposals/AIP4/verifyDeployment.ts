import fs from "fs";
import { JsonRpcProvider } from "@ethersproject/providers";
import { AIP4Action__factory } from "../../../typechain-types";
import { assertEquals } from "../../testUtils";
import dotenv from "dotenv";
dotenv.config();

const { actionAddress } = JSON.parse(
  fs.readFileSync("./scripts/proposals/AIP4/data/42161-AIP4-data.json").toString()
);

const ARB_URL = process.env.ARB_URL;
if (!ARB_URL) throw new Error("ARB_URL required");
const expectedAddressRegistry = "0x56C4E9Eb6c63aCDD19AeC2b1a00e4f0d7aBda9d3";
const expectedConstitutionHash =
  "0x9eaf992155313be93e92fd4d98aac416685297dea42413c83e639b7ddb89941b";

const main = async () => {
  const l2Provider = new JsonRpcProvider(ARB_URL);
  const aip4action = AIP4Action__factory.connect(actionAddress, l2Provider);

  assertEquals(
    expectedConstitutionHash,
    await aip4action.newConstitutionHash(),
    "action has expected constitution hash"
  );
  assertEquals(
    expectedAddressRegistry,
    await aip4action.l2GovAddressRegistry(),
    "action uses expected l2 address registry "
  );
  console.log("successfully verified");
};

main().then(() => {
  console.log("Done");
});
