import { generateArbSysArgs } from "../../genGoverningChainTargetedProposalArgs";
import { JsonRpcProvider } from "@ethersproject/providers";
import { CoreGovPropposal } from "../coreGovProposalInterface";
import fs from "fs";
import dotenv from "dotenv";
dotenv.config();
const { ARB_URL, ETH_URL } = process.env;
if (!ARB_URL) throw new Error("ARB_URL required");
if (!ETH_URL) throw new Error("ETH_URL required");

const chainIDToActionAddress = {
  42161: "0x6274106eedD4848371D2C09e0352d67B795ED516",
  421613: "0x457b79f1bb94f0af8b8d0c2a0a535fd0c8ded3ea",
};

const description = `
Category: Constitutional - Process

Abstract:
This document (“AIP-1.2”) proposes amendments to the Constitution, and The Arbitrum Foundation Amended & Restated Memorandum & Articles of Association (the “A&R M&A”) and Bylaws (the “Bylaws”) to (1) remove references to AIP-1, and (2) make other changes reflecting feedback from the community.

Motivation:
AIP-1 set out critical aspects of governance and included key governance documents for the ArbitrumDAO, and The Arbitrum Foundation which referenced AIP-1 throughout: the ArbitrumDAO Constitution (the “Constitution”), the Bylaws and the A&R M&A. However, after vigorous community debate, AIP-1 did not pass.

Rationale:
The Constitution is a foundational document that lays out the governance system and capabilities of the ArbitrumDAO; the Bylaws and A&R M&A outline The Arbitrum Foundation’s relationship with and obligations to the ArbitrumDAO. These documents should be updated, via amendment, to remove references to AIP-1 and also to reflect other changes requested by the community during the debate process over AIP-1.

Specifications:

Amendments to the Constitution (https://drive.google.com/file/d/1pIYxg9rJzIPcP0bvQAaPgmLITM9rVBIf/view?usp=share_link)
-Remove references to AIP-1, except as reference to the moment the original Constitution became effective.
-Make explicit that proposals to amend The Arbitrum Foundation’s A&R M&A and Bylaws take the form of a Constitutional AIP.
-Make explicit that the DAO may make a Non-Constitutional Funding AIP with respect to the Administrative Budget Wallet.
-Lower the threshold number of Votable Tokens required for an AIP to be posted on-chain from 5,000,000 $ARB to 1,000,000 $ARB.
-Add a new Section 5, which details the Data Availability Committee, including processes for removing and appointing Data Availability Committee members.

Amendments to the Bylaws (https://drive.google.com/file/d/1VLYNk9VYUWMl0sL2wchot6I6arHCzd4r/view?usp=share_link)
-Remove references to AIP-1.
-Clarify that the definition of “Administrative Budget Wallet” includes all assets that are contributed to or otherwise acquired by the Administrative Budget Wallet, inclusive of assets specifically approved by the ArbitrumDAO. As pointed out by the DAO in its feedback in response to AIP-1, the “Administrative Budget Wallet” defined term in the Bylaws was unclear and didn’t clearly reflect the reality of The Arbitrum Foundation’s receipt of 7.5% of the token supply upon the $ARB token genesis.
-Remove references to “Special Grants” and replace with the concept of Arbitrum ecosystem growth.
-Remove “AIP Threshold” defined term as it is not used elsewhere in the Bylaws
-Clarify that the ArbitrumDAO may replace The Arbitrum Foundation’s directors, change the number of directors, and require The Arbitrum Foundation to take certain actions.

Amendments to the A&R M&A (https://drive.google.com/file/d/1Zmi5w21skdwuC7EAe59mYBC_4fS1vqzJ/view?usp=share_link)
-Remove references to AIP-1.
`;
const main = async () => {
  const l1Provider = new JsonRpcProvider(ETH_URL);
  const l2Provider = new JsonRpcProvider(ARB_URL);
  const chainId = (await l2Provider.getNetwork()).chainId as 42161 | 421613;
  const actionAddress = chainIDToActionAddress[chainId];
  if (!actionAddress) throw new Error("Invalid chainId");

  const { l1TimelockTo, l1TimelockScheduleCallData } = await generateArbSysArgs(
    l1Provider,
    l2Provider,
    actionAddress,
    description,
    true
  );
  const proposal: CoreGovPropposal = {
    actionChainID: [chainId],
    actionAddress: [actionAddress],
    description,
    arbSysSendTxToL1Args: {
      l1Timelock: l1TimelockTo,
      calldata: l1TimelockScheduleCallData,
    },
  };
  const path = `${__dirname}/data/${chainId}-AIP1.2-data.json`;
  fs.writeFileSync(path, JSON.stringify(proposal));
  console.log("Wrote proposal data to", path);
  console.log(proposal);
};

main().then(() => {
  console.log("done");
});
