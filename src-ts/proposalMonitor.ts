import { Provider } from "@ethersproject/providers";
import {
  L2ArbitrumGovernor,
  L2ArbitrumGovernor__factory,
} from "../typechain-types";
import {
  ProposalCreatedEvent,
  ProposalCreatedEventObject,
} from "../typechain-types/src/L2ArbitrumGovernor";
import { TypedEvent } from "../typechain-types/common";
import { wait } from "./utils";
import { EventArgs } from "@arbitrum/sdk/dist/lib/dataEntities/event";
import {
  createRoundTripGenerator,
  ProposalStageManager,
} from "./proposalStage";
import { Signer } from "ethers";
import { formatBytes32String } from "ethers/lib/utils";

export declare type EventArgs2<T> = T extends TypedEvent<infer _, infer TObj>
  ? TObj
  : never;

class GovernorProposalMonitor {
  constructor(
    public readonly governorAddress: string,
    public readonly governorProvider: Provider,
    public readonly pollingIntervalMs: number,
    public readonly blockLag: number,

    // CHRIS: TOD: cant we get rid of these?
    public readonly arbOneSigner: Signer,
    public readonly l1Signer: Signer,
    public readonly novaSigner: Signer
  ) {}

  public async start() {
    let blockThen =
      (await this.governorProvider.getBlockNumber()) - this.blockLag;
    await wait(this.pollingIntervalMs);

    while (true) {
      const blockNow =
        (await this.governorProvider.getBlockNumber()) - this.blockLag;

      const governor = L2ArbitrumGovernor__factory.connect(
        this.governorAddress,
        this.governorProvider
      );

      const proposalCreatedFilter =
        governor.filters[
          "ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)"
        ]();
      const logs = (
        await this.governorProvider.getLogs({
          fromBlock: blockThen,
          toBlock: blockNow - 1,
          ...proposalCreatedFilter,
        })
      ).map(
        (l) =>
          governor.interface.parseLog(l)
            .args as unknown as ProposalCreatedEventObject
      );
      for (const log of logs) {
        const gen = createRoundTripGenerator(
          formatBytes32String(log.proposalId.toHexString()),
          log.targets[0],
          log.values[0],
          log.calldatas[0],
          log.description,
          this.governorAddress,

          this.arbOneSigner,
          this.l1Signer,
          this.novaSigner
        );

        // these arent really proposal stages, they're more like tx execution awaiters
        // we have some polling mechanism - it's not an event it's a general status monitor
        // 

        const propStageManager = new ProposalStageManager(
          gen,
          this.pollingIntervalMs
        );

        const runner = propStageManager.run()

        // CHRIS: TODO: catch errors in that by logging or throwing?
        // CHRIS: TODO: we should probably reject this current promise somehow
      }

      await wait(this.pollingIntervalMs);
    }
  }

  public stop() {}
}
