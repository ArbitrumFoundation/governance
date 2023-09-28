import { Wallet, BigNumber } from "ethers";
import { SecurityCouncilNomineeElectionGovernor__factory } from "../typechain-types";
import { JsonRpcProvider } from "@ethersproject/providers";
import { getL1BlockNumberFromL2 } from "./utils";

export class SecurityCouncilElectionCreator {
  public readonly retryTime = 10 * 1000;
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

    const l1BlockNumber = await getL1BlockNumberFromL2(this.govChainProvider);
    
    const { timestamp: parentChainTimestamp } = await this.parentChainProvider.getBlock(
      l1BlockNumber.toNumber()
    );

    const electionTimestamp = await gov.electionToTimestamp(await gov.electionCount());

    const timeToElectionSeconds = electionTimestamp.sub(parentChainTimestamp).toNumber();
    if (timeToElectionSeconds <= 0) {
      const res = await gov.createElection();
      await res.wait();
      setTimeout(this.run, this.retryTime);
    } else {
      console.log(`Next election starts in ${timeToElectionSeconds} seconds`);
      setTimeout(
        this.run.bind(this),
        Math.max(
          Math.min(timeToElectionSeconds * 1000, 2147483647 /**32 bit int max */),
          this.retryTime
        )
      );
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
