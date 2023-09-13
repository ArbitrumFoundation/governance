import { Wallet } from "ethers";
import { Multicall2__factory } from "../token-bridge-contracts/build/types";
import { SecurityCouncilNomineeElectionGovernor__factory } from "../typechain-types";

export class SecurityCouncilElectionCreator {
  retryTime = 10 * 1000;
  public constructor(
    public readonly connectedSigner: Wallet,
    public readonly nomineeElectionGovAddress: string,
    public readonly multicallAddress: string
  ) {}

  public async checkAndCreateElection() {
    const multicall = Multicall2__factory.connect(
      this.multicallAddress,
      this.connectedSigner.provider
    );
    const gov = SecurityCouncilNomineeElectionGovernor__factory.connect(
      this.nomineeElectionGovAddress,
      this.connectedSigner.provider
    );
    const parentChainTimestamp = await multicall.getCurrentBlockTimestamp();
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
