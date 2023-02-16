import { Signer } from "ethers";
import { L2ArbitrumToken__factory } from "../typechain-types";
import {
  getDeployersAndConfig as getDeployersAndConfig,
  loadDeployedContracts,
} from "./providerSetup";
import { TransferEvent } from "../typechain-types/src/Util.sol/IERC20VotesUpgradeable";
import { Recipients } from "./testUtils";

async function transferDaoAllocations(
  initialTokenRecipient: Signer,
  tokenAddress: string,
  daoRecipients: Recipients
) {
  const token = L2ArbitrumToken__factory.connect(tokenAddress, initialTokenRecipient);

  for (const rec of Object.keys(daoRecipients)) {
    const filter = token.filters["Transfer(address,address,uint256)"](
      await initialTokenRecipient.getAddress(),
      rec
    );

    const logs = await initialTokenRecipient.provider!.getLogs({
      fromBlock: 0,
      toBlock: "latest",
      ...filter,
    });

    if (logs.length === 0) {
      // this recipient has not been transferred to yet
      await (await token.transfer(rec, daoRecipients[rec])).wait();
    } else if (logs.length === 1) {
      const { value } = token.interface.parseLog(logs[0]).args as TransferEvent["args"];

      if (!value.eq(daoRecipients[rec])) {
        throw new Error(
          `Incorrect value sent to ${rec}:${daoRecipients[rec].toString()}:${value.toString()}`
        );
      }
    } else {
      console.error(logs);
      throw new Error(`Too many transfer logs for ${rec}`);
    }
  }
}

export const allocateTokens = async () => {};

async function main() {
  console.log("Get deployers and signers");
  const { arbDeployer, daoRecipients } = await getDeployersAndConfig();

  const deployedContracts = loadDeployedContracts();
  console.log(`Cache: ${JSON.stringify(deployedContracts, null, 2)}`);

  console.log("Distribute to DAOs");
  await transferDaoAllocations(arbDeployer, deployedContracts.l2Token!, daoRecipients);
  console.log("Allocation finished!");
}

main().then(() => console.log("Done."));
