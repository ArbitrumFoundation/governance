import { Wallet, BigNumber } from "ethers";
import { SecurityCouncilNomineeElectionGovernor__factory } from "../typechain-types";
import { JsonRpcProvider } from "@ethersproject/providers";
import { getL1BlockNumberFromL2 } from "./utils";

export class SecurityCouncilElectionTracker {
  public readonly retryTime = 10 * 1000;
  public constructor(
    public readonly govChainProvider: JsonRpcProvider,
    public readonly parentChainProvider: JsonRpcProvider,
    public readonly nomineeElectionGovAddress: string,
    public readonly connectedSigner?: Wallet
  ) {}

  public async checkAndCreateElection() {
    const gov = SecurityCouncilNomineeElectionGovernor__factory.connect(
      this.nomineeElectionGovAddress,
      this.govChainProvider
    );

    const l1BlockNumber = await getL1BlockNumberFromL2(this.govChainProvider);

    const { timestamp: parentChainTimestamp } = await this.parentChainProvider.getBlock(
      l1BlockNumber.toNumber()
    );

    const electionTimestamp = await gov.electionToTimestamp(await gov.electionCount());

    const timeToElectionSeconds = electionTimestamp.sub(parentChainTimestamp).toNumber();
    if (timeToElectionSeconds <= 0) {
      console.log("Ready to Create Election");
      if (this.connectedSigner) {
        const govWriter = SecurityCouncilNomineeElectionGovernor__factory.connect(
          this.nomineeElectionGovAddress,
          this.connectedSigner
        );
        const res = await govWriter.createElection();
        await res.wait();
      }
      setTimeout(this.run.bind(this), this.retryTime);
    } else {
      console.log(`Next election can  be initiated at timestamp ${electionTimestamp}; that's in ${secondsToString(timeToElectionSeconds)}`);
      setTimeout(
        this.run.bind(this),
        Math.max(
          Math.min(timeToElectionSeconds * 1000 / 2, 2147483647 /**32 bit int max */),
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
      setTimeout(this.run.bind(this), this.retryTime);
    }
  }
}

function secondsToString(seconds: number) {
  var numdays = Math.floor((seconds % 31536000) / 86400);
  var numhours = Math.floor(((seconds % 31536000) % 86400) / 3600);
  var numminutes = Math.floor((((seconds % 31536000) % 86400) % 3600) / 60);
  var numseconds = (((seconds % 31536000) % 86400) % 3600) % 60;
  return (
    numdays + " days " + numhours + " hours " + numminutes + " minutes " + numseconds + " seconds"
  );
}
