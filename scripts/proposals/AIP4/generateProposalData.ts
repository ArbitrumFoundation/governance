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
  42161: "0x85792f6BF346e3Bfd3A275318aDd2c44A1058447",
  421613: "0x85792f6BF346e3Bfd3A275318aDd2c44A1058447",
};

const description = `
Proposal: Update Security Council Election Start Date to Ensure Time for Security Audit

Category: Constitutional - Process

High Level Overview
The ArbitrumDAO Constitution specifies that the first Security Council election should start on the 15th September alongside a specification for the election.

An on-chain implementation of the entire election is still a work in progress. The Arbitrum Foundation has sponsored the implementation of a smart contract suite by Offchain Labs, an extension of Tally’s user interface, and the respective audits.

This proposal seeks to revise the ArbitrumDAO Constitution to provide flexibility for the start date of the election. If passed by a Constitutional Vote, the new start date will be on the 15th September or the earliest possible date in which an on-chain election can begin.

The motivation to change the election’s start date is to provide time for the implementation to be completed, security audits to be performed, for the community to gain confidence in the quality of its implementation and for the Arbitrum DAO to vote on a separate Constitutional AIP to install an on-chain election system.

The overarching goal is to still allow the election to begin on the 15th September, but it is prudent to provide leeway and ensure all parties, especially the Arbitrum DAO, are confident in the election software’s security and completeness.

Path to a Smart Contract Enabled Election
This proposal seeks approval from the Arbitrum DAO that the first and all subsequent security elections should be performed via the on-chain election process.

The activation of the Security Council election is dependent on:

Complete implementation for the on-chain smart contracts,
Complete implementation of the user interface,
Smart contract audit by a highly regarded auditing firm,
All parties, including the Arbitrum DAO, have gained confidence in the implementation’s completeness and security,
Successful Constitutional Vote by the DAO to install the new election software.
A vote on this proposal is approving that the above conditions are mandatory for any election software before it can be installed into the on-chain smart contracts.

Modified Start Date for Election
The implementation sponsored by the Arbitrum Foundation should be ready for the start date of the 15th September.

Even so, given the naunces of implementation details and the potential security risks to a critical part of the system, we believe it is still prudent to provide leeway and extra time for the Security Council elections to begin some time after the required date set out by The Arbitrum Foundation.

After all, it is not just about having a complete implementation, but ensuring all parties have confidence that all efforts have made been to minimize the risk of bugs in the implementation.

Revision to ArbitrumDAO Constitution
The revised text focuses on the election beginning at the earliest possible date from the 15th September. Additionally, the election can only begin once an on-chain election system is installed via a separate Constitutional Vote.

All future elections can begin six months after the previous election. As such, the chosen date for the first election will decide the earliest start date for the next election.

For extra clarity in the text, we have renamed “September Cohort” to “First Cohort” and “March Cohort” to “Second Cohort”

Finally, to remove any ambiguity, all security council members are expected to serve the time until the new Security Council members are installed in the respective smart contracts.

Current text of ArbitrumDAO Constitution:
The Security Council has 12 members, who are divided into a September Cohort of 6 members, and a March Cohort of 6 members. Every year on September 15, 12:00 UTC, an election starts for the 6 September Cohort seats; and every year on March 15, 12:00 UTC, an election starts for the 6 March Cohort seats.

This means that the initial September Cohort will serve an initial term of 6 months, whereas the initial March Cohort will serve an initial term of 1 year.

The initial Security Council Cohorts were determined by randomly splitting the 12 members into two 6-member cohorts - 6 members in the September Cohort and 6 members in the March Cohort. The members of the initial Security Council Cohorts are detailed in a transparency report here.

Proposed Revision of Arbitrum Constitution:
The Security Council has 12 members, who are divided into two Cohorts of 6 members.

The initial Security Council Cohorts were determined by randomly splitting the 12 members into two 6-member cohorts - 6 members in the ‘First Cohort’ and 6 members in the ‘Second Cohort’. The members of the initial Security Council Cohorts are detailed in a transparency report here.

The first security election is scheduled to begin on the 15th September 2023 or the earliest possible date. The election can only begin upon the availability of an on-chain election process that was approved and installed by the Arbitrum DAO. This first election replaces the ‘First Cohort’. The next election replaces the ‘Second Cohort,’ and so forth.

The date chosen for the first election will form the basis for all future elections. Every election should begin 6 months after the previous election has started and it will replace its respective cohort of 6 members.

All Security Council members are expected to serve their term until the election is complete and the new Security Council members are installed.
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
  const path = `${__dirname}/data/${chainId}-AIP4-data.json`;
  fs.writeFileSync(path, JSON.stringify(proposal, null, 2));
  console.log("Wrote proposal data to", path);
  console.log(proposal);
};

main().then(() => {
  console.log("done");
});
