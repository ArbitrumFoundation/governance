import { BigNumber, Signer, Wallet } from "ethers";
import { L2ArbitrumToken__factory } from "../typechain-types";
import {
  getDaoRecipientsEscrowSigner,
  getDeployersAndConfig as getDeployersAndConfig,
  loadDaoRecipients,
  loadDeployedContracts,
} from "./providerSetup";
import { TransferEvent } from "../typechain-types/src/Util.sol/IERC20VotesUpgradeable";
import { Recipients, assertEquals, assertNumbersEquals } from "./testUtils";
import { JsonRpcProvider } from "@ethersproject/providers";
import { parseEther } from "ethers/lib/utils";

async function transferDaoAllocations(
  daoEscrowSigner: Signer,
  tokenAddress: string,
  daoRecipients: Recipients
) {
  const token = L2ArbitrumToken__factory.connect(tokenAddress, daoEscrowSigner);

  for (const rec of Object.keys(daoRecipients)) {
    const filter = token.filters["Transfer(address,address,uint256)"](
      await daoEscrowSigner.getAddress(),
      rec
    );

    const logs = await daoEscrowSigner.provider!.getLogs({
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

async function main() {
  console.log("Get deployers and signers");
  const { arbDeployer, deployerConfig } = await getDeployersAndConfig();
  const daoRecipients = loadDaoRecipients();

  const daoSigner = getDaoRecipientsEscrowSigner(arbDeployer.provider! as JsonRpcProvider);
  if ((await daoSigner.getBalance()).eq(0)) {
    throw new Error("Dao escrow account has no eth for gas");
  }

  const daoTotal = Object.values(daoRecipients).reduce((a, b) => a.add(b));
  assertNumbersEquals(
    daoTotal,
    parseEther(deployerConfig.L2_NUM_OF_TOKENS_FOR_DAO_RECIPIENTS),
    "Unexpected total amount for dao recipients"
  );

  const deployedContracts = loadDeployedContracts();
  console.log(`Cache: ${JSON.stringify(deployedContracts, null, 2)}`);

  console.log("Distribute to DAOs");
  await transferDaoAllocations(daoSigner, deployedContracts.l2Token!, daoRecipients);
  console.log("Allocation finished!");
}

main().then(() => console.log("Done."));
