import { Provider } from "@ethersproject/providers";
import { CoreGovProposal, NonEmergencySCProposal } from "./coreGovProposalInterface";
import { ArbSys__factory, UpgradeExecRouteBuilder__factory } from "../../typechain-types";
import { BigNumberish, BytesLike } from "ethers";

async function _getCallDataFromRouteBuilder(
  provider: Provider,
  routeBuilderAddress: string,
  actionChainIds: number[],
  actionAddresses: string[],
  timelockSalt: BytesLike,
  actionValues: BigNumberish[] | undefined,
  actionDatas: BytesLike[] | undefined,
  predecessor: BytesLike | undefined
) {
  const routeBuilder = UpgradeExecRouteBuilder__factory.connect(routeBuilderAddress, provider);
  if (actionValues && actionDatas && predecessor) {
    return (
      await routeBuilder.createActionRouteData(
        actionChainIds,
        actionAddresses,
        actionValues,
        actionDatas,
        predecessor,
        timelockSalt
      )
    )[1];
  } else if (actionValues || actionDatas || predecessor) {
    throw new Error(
      "Custom actionValues, actionDatas and predecessor must all be provided if any are"
    );
  } else {
    return (
      await routeBuilder.createActionRouteDataWithDefaults(
        actionChainIds,
        actionAddresses,
        timelockSalt
      )
    )[1];
  }
}

async function _buildProposal(
  description: string,
  provider: Provider,
  routeBuilderAddress: string,
  actionChainIds: number[],
  actionAddresses: string[],
  timelockSalt: BytesLike,
  actionValues: BigNumberish[] | undefined,
  actionDatas: BytesLike[] | undefined,
  predecessor: BytesLike | undefined
): Promise<CoreGovProposal> {
  let calldata = await _getCallDataFromRouteBuilder(
    provider,
    routeBuilderAddress,
    actionChainIds,
    actionAddresses,
    timelockSalt,
    actionValues,
    actionDatas,
    predecessor
  );

  // The route builder encodes the sendTxToL1 call in the calldata it returns.
  // Proposal submission on the governor has this value passed in as a separate parameter;
  // so here we decode to retrieve the appropriate calldata.
  const decoded = ArbSys__factory.createInterface().decodeFunctionData("sendTxToL1", calldata);

  return {
    actionChainIds,
    actionAddresses,
    description,
    arbSysSendTxToL1Args: {
      l1Timelock: decoded[0],
      calldata: decoded[1],
    },
  };
}

export function buildProposalCustom(
  description: string,
  provider: Provider,
  routeBuilderAddress: string,
  actionChainIds: number[],
  actionAddresses: string[],
  timelockSalt: BytesLike,
  actionValues: BigNumberish[],
  actionDatas: BytesLike[],
  predecessor: BytesLike
): Promise<CoreGovProposal> {
  return _buildProposal(
    description,
    provider,
    routeBuilderAddress,
    actionChainIds,
    actionAddresses,
    timelockSalt,
    actionValues,
    actionDatas,
    predecessor
  );
}

export function buildProposal(
  description: string,
  provider: Provider,
  routeBuilderAddress: string,
  actionChainIds: number[],
  actionAddresses: string[],
  timelockSalt: BytesLike
): Promise<CoreGovProposal> {
  return _buildProposal(
    description,
    provider,
    routeBuilderAddress,
    actionChainIds,
    actionAddresses,
    timelockSalt,
    undefined,
    undefined,
    undefined
  );
}

export async function buildNonEmergencySecurityCouncilProposal(
  description: string,
  provider: Provider,
  routeBuilderAddress: string,
  actionChainIds: number[],
  actionAddresses: string[],
  timelockSalt: BytesLike,
  actionValues?: BigNumberish[],
  actionDatas?: BytesLike[],
  predecessor?: BytesLike
): Promise<NonEmergencySCProposal> {
  let calldata = await _getCallDataFromRouteBuilder(
    provider,
    routeBuilderAddress,
    actionChainIds,
    actionAddresses,
    timelockSalt,
    actionValues,
    actionDatas,
    predecessor
  );

  return {
    actionChainIds,
    actionAddresses,
    description,
    l2TimelockScheduleArgs: {
      target: "0x0000000000000000000000000000000000000064", // arb sys address
      calldata,
    },
  };
}
