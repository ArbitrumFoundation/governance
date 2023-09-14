import { Wallet } from "ethers";
import { SecurityCouncilNomineeElectionGovernor__factory } from "../typechain-types";
import { ArbitrumProvider } from "@arbitrum/sdk";
import { JsonRpcProvider } from "@ethersproject/providers";
export class SecurityCouncilElectionCreator {
  retryTime = 10 * 1000;
  public constructor(
    public readonly connectedSigner: Wallet,
    public readonly govChainProvider: JsonRpcProvider,
    public readonly parentChainProvider: JsonRpcProvider,
    public readonly nomineeElectionGovAddress: string
  ) {}

  public async checkAndCreateElection() {
    const gov = SecurityCouncilNomineeElectionGovernor__factory.connect(
      this.nomineeElectionGovAddress,
      this.connectedSigner.provider
    );
    const arbProvider = new ArbitrumProvider(this.govChainProvider);

    const { l1BlockNumber } = await arbProvider.getBlock(await arbProvider.getBlockNumber());
    const { timestamp: parentChainTimestamp } = await this.parentChainProvider.getBlock(
      l1BlockNumber
    );

    const electionTimestamp = await gov.electionToTimestamp(await gov.electionCount());

    const timeToElectionSeconds = electionTimestamp.sub(parentChainTimestamp).toNumber();
    if (timeToElectionSeconds <= 0) {
      const res = await gov.createElection();
      await res.wait();
      setTimeout(this.run, this.retryTime);
    } else {
      console.log(`Next election starts in ${timeToElectionSeconds} seconds`);
      setTimeout(this.run, Math.max(timeToElectionSeconds * 1000, this.retryTime));
    }
  }

  public async run() {
    try {
      this.checkAndCreateElection();
    } catch (e) {
      console.log("SecurityCouncilElectionCreator error:", e);
      setTimeout(this.run, this.retryTime);
    }
  }
}
