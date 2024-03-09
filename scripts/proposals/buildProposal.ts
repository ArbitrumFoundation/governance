import { Provider } from "@ethersproject/providers";
import { CoreGovProposal, NonEmergencySCProposal } from "./coreGovProposalInterface";
import { ArbSys__factory, UpgradeExecRouteBuilder__factory } from "../../typechain-types";
import { BigNumberish, BytesLike, constants } from "ethers";
import { ARB_SYS_ADDRESS } from "@arbitrum/sdk/dist/lib/dataEntities/constants";
import { keccak256 } from "ethers/lib/utils";
import { defaultAbiCoder } from "@ethersproject/abi";

function _generateL1TimelockSalt(actionChainIds: number[], actionAddresses: string[]) {
  return keccak256(
    defaultAbiCoder.encode(["uint256[]", "string[]"], [actionChainIds, actionAddresses])
  );
}

async function _getCallDataFromRouteBuilder(
  provider: Provider,
  routeBuilderAddress: string,
  actionChainIds: number[],
  actionAddresses: string[],
  timelockSalt: string,
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
    )[1]; // returns [ArbSysAddress, Proposal Data]
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
  provider: Provider,
  routeBuilderAddress: string,
  actionChainIds: number[],
  actionAddresses: string[],
  actionValues: BigNumberish[] | undefined,
  actionDatas: BytesLike[] | undefined,
  predecessor: BytesLike | undefined
): Promise<CoreGovProposal> {
  const timelockSalt = _generateL1TimelockSalt(actionChainIds, actionAddresses);

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
    arbSysSendTxToL1Args: {
      l1Timelock: decoded[0],
      calldata: decoded[1],
    },
  };
}

export function buildProposalCustom(
  provider: Provider,
  routeBuilderAddress: string,
  actionChainIds: number[],
  actionAddresses: string[],
  actionValues: BigNumberish[],
  actionDatas: BytesLike[],
  predecessor: BytesLike
): Promise<CoreGovProposal> {
  return _buildProposal(
    provider,
    routeBuilderAddress,
    actionChainIds,
    actionAddresses,
    actionValues,
    actionDatas,
    predecessor
  );
}

export function buildProposal(
  provider: Provider,
  routeBuilderAddress: string,
  actionChainIds: number[],
  actionAddresses: string[]
): Promise<CoreGovProposal> {
  return _buildProposal(
    provider,
    routeBuilderAddress,
    actionChainIds,
    actionAddresses,
    undefined,
    undefined,
    undefined
  );
}

export async function buildNonEmergencySecurityCouncilProposal(
  provider: Provider,
  routeBuilderAddress: string,
  actionChainIds: number[],
  actionAddresses: string[],
  actionValues?: BigNumberish[],
  actionDatas?: BytesLike[],
  predecessor?: BytesLike
): Promise<NonEmergencySCProposal> {
  const timelockSalt = _generateL1TimelockSalt(actionChainIds, actionAddresses);

  // get data; unlike CoreProposal path, we keep the encoded sendTxToL1 call
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
    l2TimelockScheduleArgs: {
      target: ARB_SYS_ADDRESS, // arb sys address
      data: calldata,
      predecessor: predecessor?.toString() || constants.HashZero,
      salt: timelockSalt,
    },
  };
}
