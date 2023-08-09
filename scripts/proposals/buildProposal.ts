import { Provider } from "@ethersproject/providers";
import { CoreGovProposal } from "./coreGovProposalInterface";
import { ArbSys__factory, UpgradeExecRouteBuilder__factory } from "../../typechain-types";
import { BigNumberish, BytesLike, ethers } from "ethers";

async function _buildProposal(
  description: string,
  provider: Provider,
  routeBuilderAddress: string,
  actionChainIds: number[],
  actionAddresses: string[],
  actionValues: BigNumberish[] | undefined,
  actionDatas: BytesLike[] | undefined,
  predecessor: BytesLike | undefined,
  timelockSalt: BytesLike | undefined
): Promise<CoreGovProposal> {
  const routeBuilder = UpgradeExecRouteBuilder__factory.connect(
    routeBuilderAddress,
    provider
  );
  
  let calldata;

  if (actionValues && actionDatas && predecessor && timelockSalt) {
    [, calldata] = await routeBuilder.createActionRouteData(
      actionChainIds,
      actionAddresses,
      actionValues,
      actionDatas,
      predecessor,
      timelockSalt
    );
  }
  else {
    [, calldata] = await routeBuilder.createActionRouteDataWithDefaults(
      actionChainIds,
      actionAddresses,
      timelockSalt || ethers.constants.HashZero,
    );
  }

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
  actionValues: BigNumberish[],
  actionDatas: BytesLike[],
  predecessor: BytesLike,
  timelockSalt: BytesLike
): Promise<CoreGovProposal> {
  return _buildProposal(
    description,
    provider,
    routeBuilderAddress,
    actionChainIds,
    actionAddresses,
    actionValues,
    actionDatas,
    predecessor,
    timelockSalt
  );
}

export function buildProposal(
  provider: Provider,
  routeBuilderAddress: string,
  actionChainIds: number[],
  actionAddresses: string[],
  description: string,
  timelockSalt: BytesLike | undefined = undefined
): Promise<CoreGovProposal> {
  return _buildProposal(
    description,
    provider,
    routeBuilderAddress,
    actionChainIds,
    actionAddresses,
    undefined,
    undefined,
    undefined,
    timelockSalt
  )
}
