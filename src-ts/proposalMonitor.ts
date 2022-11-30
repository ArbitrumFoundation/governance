import { Provider } from "@ethersproject/providers";
import { L2ArbitrumGovernor } from "../typechain-types";
import { wait } from "./utils";

class ProposalMonitor {
  constructor(
    public readonly governorAddress: string,
    public readonly provider: Provider,
    public readonly pollingIntervalMs: number
  ) {}

  public async start() {
    while (true) {
      await wait(this.pollingIntervalMs);
    }
  }

  public stop() {}
}
