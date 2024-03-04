export interface CoreGovPropposal {
  actionChainID: number[];
  actionAddress: string[];
  description?: string;
  arbSysSendTxToL1Args: {
    l1Timelock: string;
    calldata: string;
  };
}

export interface CoreGovProposal {
  actionChainIds: number[];
  actionAddresses: string[];
  description?: string;
  arbSysSendTxToL1Args: {
    l1Timelock: string;
    calldata: string;
  };
}

export interface NonEmergencySCProposal {
  actionChainIds: number[];
  actionAddresses: string[];
  description?: string;
  l2TimelockScheduleArgs: {
    target: "0x0000000000000000000000000000000000000064"; // arb sys address
    calldata: string;
  };
}
