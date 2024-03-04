import yargs from "yargs";
import { JsonRpcProvider } from "@ethersproject/providers";
import { utils, constants } from "ethers";
import * as fs from "fs";
import {
  buildProposal,
  buildProposalCustom,
  buildNonEmergencySecurityCouncilProposal,
} from "./proposals/buildProposal";
import { keccak256 } from "ethers/lib/utils";
import { defaultAbiCoder } from "@ethersproject/abi";

const scmMainnetContracts = JSON.parse(
  fs.readFileSync("./files/mainnet/scmDeployment.json").toString()
);

let actionIface = new utils.Interface(["function perform() external"]);
const defaultUpgradeData = actionIface.encodeFunctionData("perform");
console.log();

const options = yargs(process.argv.slice(2))
  .options({
    govChainProviderRPC: {
      type: "string",
      demandOption: true,
      description: "RPC url string for governance chain provider",
    },
    actionChainIds: {
      type: "array",
      number: true,
      demandOption: true,
      description:
        "Chain ids of the chains with the action contracts in proposal; indices should correspond to indices in actionAddresses",
    },
    actionAddresses: {
      type: "array",
      string: true,
      demandOption: true,
      description:
        "Addresses for action contracts in proposal; indices should correspond to indices in actionChainIds",
    },

    description: {
      type: "string",
      demandOption: false,
      description: "Either proposalDescription or pathToProposalDescription are required",
    },
    pathToDescription: {
      type: "string",
      demandOption: false,
      description: "Either proposalDescription or pathToProposalDescription are required",
    },
    writeToJsonPath: {
      type: "string",
      demandOption: false,
      description: "JSON file to write to",
    },
    routeBuilderAddress: {
      type: "string",
      demandOption: false,
      description:
        "RouteBuilder contract address. If not provided, will attempt to find in deployment config",
    },
    nonEmergencySCproposal: {
      type: "boolean",
      demandOption: false,
      description: "Create proposal data for a non-emergency security council proposal if set true",
      defaultValue: false,
    },
    upgradeValues: {
      type: "array",
      number: true,
      demandOption: false,
      description: "If not provided, all will default all to 0",
    },
    upgradeDatas: {
      type: "array",
      string: true,
      demandOption: false,
      description: "If not provided, all will default all to perform()",
    },
    predecessor: {
      type: "string",
      demandOption: false,
      defaultValue: constants.HashZero,
    },
  })
  .parseSync() as {
  govChainProviderRPC: string;
  actionChainIds: number[];
  actionAddresses: string[];
  description?: string;
  pathToDescription?: string;
  writeToJsonPath?: string;
  routeBuilderAddress: string;
  upgradeValues?: number[];
  upgradeDatas?: string[];
  nonEmergencySCproposal: boolean;
  predecessor: string;
};

const main = async () => {
  const govChainProvider = new JsonRpcProvider(options.govChainProviderRPC);

  let routeBuilderAddress = await (async () => {
    if (options.routeBuilderAddress) return options.routeBuilderAddress;
    const { chainId } = await govChainProvider.getNetwork();
    if (chainId === 42161) {
      return scmMainnetContracts.upgradeExecRouteBuilder;
    }
    throw new Error(`Need to provide an upgradeExecRouteBuilder for chain ${chainId}`);
  })();

  const description =
    options.description ||
    (options.pathToDescription && fs.readFileSync(options.pathToDescription).toString());
  if (!description) throw new Error("Need to provide a description or path to description");

  const timelockSalt = keccak256(defaultAbiCoder.encode(["string"], [description]));

  if (options.nonEmergencySCproposal) {
    console.log("Creating non-emergency securiyy council proposal:");
    const proposalData = await buildNonEmergencySecurityCouncilProposal(
      description,
      govChainProvider,
      routeBuilderAddress,
      options.actionChainIds,
      options.actionAddresses,
      timelockSalt,
      options.upgradeValues,
      options.upgradeDatas,
      options.predecessor
    );
    console.log("Proposal data:");
    console.log(proposalData);
    if (options.writeToJsonPath) {
      console.log("Writng to file:", options.writeToJsonPath);
      fs.writeFileSync(options.writeToJsonPath, JSON.stringify(proposalData, null, 2));
      console.log("done");
    }
    return;
  } else {
    console.log("Creating core gov proposal");
  }

  const proposalData = await (() => {
    if (!options.upgradeValues && !options.upgradeDatas && !options.predecessor) {
      console.log("Using defaults for upgradeValues, upgradeDatas, and predecessor");
      return buildProposal(
        description,
        govChainProvider,
        routeBuilderAddress,
        options.actionChainIds,
        options.actionAddresses,
        timelockSalt
      );
    }

    console.log("Custom values passed in:");
    const upgradeValues = options.upgradeValues || options.actionChainIds.map(() => constants.Zero);
    const upgradeDatas =
      options.upgradeDatas || options.actionChainIds.map(() => defaultUpgradeData);
    let predecessor = options.predecessor;
    return buildProposalCustom(
      description,
      govChainProvider,
      routeBuilderAddress,
      options.actionChainIds,
      options.actionAddresses,
      timelockSalt,
      upgradeValues,
      upgradeDatas,
      predecessor
    );
  })();
  console.log("Proposal data:");
  console.log(proposalData);
  if (options.writeToJsonPath) {
    console.log("Writng to file:", options.writeToJsonPath);
    fs.writeFileSync(options.writeToJsonPath, JSON.stringify(proposalData, null, 2));
    console.log("done");
  }
};
main();
