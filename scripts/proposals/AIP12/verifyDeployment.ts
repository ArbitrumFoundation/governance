import fs from "fs";
import { JsonRpcProvider } from "@ethersproject/providers";
import { AIP1Point2Action__factory } from "../../../typechain-types";
import { assertEquals, assertNumbersEquals } from "../../testUtils";

import { utils } from "ethers";
import dotenv from "dotenv";
dotenv.config();

const { actionAddress } = JSON.parse(
  fs.readFileSync("./scripts/proposals/AIP12/data/42161-AIP1.2-data.json").toString()
);

const ARB_URL = process.env.ARB_URL;
if (!ARB_URL) throw new Error("ARB_URL required");
const expectedAddressRegistry = "0x56C4E9Eb6c63aCDD19AeC2b1a00e4f0d7aBda9d3";
const expectedConstitutionHash =
  "0xaed12f8f0c5c303e864e3ec9cbea935ae0b7948d0d35790071de19c30e37a9fb";
const expectedThreshold = utils.parseEther("1000000");

const main = async () => {
  const l2Provider = new JsonRpcProvider(ARB_URL);
  const aip21action = AIP1Point2Action__factory.connect(actionAddress, l2Provider);

  assertEquals(
    expectedConstitutionHash,
    await aip21action.newConstitutionHash(),
    "action has expected constitution hash"
  );
  assertEquals(
    expectedAddressRegistry,
    await aip21action.l2GovAddressRegistry(),
    "action uses expected l2 address registry "
  );
  assertNumbersEquals(expectedThreshold, await aip21action.newProposalThreshold(), "action uses expected proposal threshold");
  console.log("successfully verified");
};

main().then(() => {
  console.log("Done");
});
