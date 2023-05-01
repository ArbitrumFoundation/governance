export interface CoreGovPropposal {
    actionChainID: number;
    actionAddress: string;
    description: string;
    arbSysSendTxToL1Args: {
        l1Timelock: string;
        calldata: string
    }
}