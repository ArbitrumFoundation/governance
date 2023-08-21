export interface CoreGovPropposal {
    actionChainID: number | number[];
    actionAddress: string | string[];
    description: string;
    arbSysSendTxToL1Args: {
        l1Timelock: string;
        calldata: string
    }
}