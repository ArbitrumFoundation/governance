import { Wallet } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { testSetup } from "../test-ts/testSetup";
import {
  ArbitrumTimelock,
  ArbitrumTimelock__factory,
  FixedDelegateErc20Wallet__factory,
  L2ArbitrumGovernor__factory,
  L2ArbitrumToken__factory,
  L2GovernanceFactory__factory,
  UpgradeExecutor__factory,
} from "../typechain-types";

const deployGovernance = async (): Promise<ArbitrumTimelock> => {
  console.log("Get deployers and signers");
  const { l2Deployer, l2Signer } = await testSetup();

  console.log("Deploy L2 logic contracts");
  const timelockLogic = await new ArbitrumTimelock__factory(l2Deployer).deploy();
  const governorLogic = await new L2ArbitrumGovernor__factory(l2Deployer).deploy();
  const fixedDelegateLogic = await new FixedDelegateErc20Wallet__factory(l2Deployer).deploy();
  const l2TokenLogic = await new L2ArbitrumToken__factory(l2Deployer).deploy();
  const upgradeExecutor = await new UpgradeExecutor__factory(l2Deployer).deploy();

  console.log("Deploy L2 governance factory");
  const l2GovernanceFactory = await new L2GovernanceFactory__factory(l2Deployer).deploy(
    timelockLogic.address,
    governorLogic.address,
    timelockLogic.address,
    fixedDelegateLogic.address,
    governorLogic.address,
    l2TokenLogic.address,
    upgradeExecutor.address
  );

  console.log("Initialize L2 governance");
  const initialSupply = parseEther("1");
  const l2TimeLockDelay = 7;
  const l2SignerAddr = await l2Signer.getAddress();
  // we use a non zero dummy address for the l1 token
  // it doesnt exist yet but we plan to upgrade the l2 token contract add this address
  const l1TokenAddress = "0x0000000000000000000000000000000000000001";
  const sevenSecurityCouncil = Wallet.createRandom();
  await l2GovernanceFactory.deployStep1(
    {
      _l2MinTimelockDelay: l2TimeLockDelay,
      _l2TokenInitialSupply: initialSupply,
      _upgradeProposer: sevenSecurityCouncil.address,
      _coreQuorumThreshold: 5,
      _l1Token: l1TokenAddress,
      _treasuryQuorumThreshold: 3,
      _proposalThreshold: 100,
      _votingDelay: 10,
      _votingPeriod: 10,
      _minPeriodAfterQuorum: 1,
      _l2InitialSupplyRecipient: l2SignerAddr,
    },

    { gasLimit: 30000000 }
  );

  return timelockLogic;
};

const verifyDeployment = async (timelockLogic: string): Promise<Boolean> => {
  const { l2Deployer } = await testSetup();

  let code = await l2Deployer.provider?.getCode(timelockLogic);
  console.log(code);
  if (code == "0x") {
    return false;
  }

  return true;
};

async function main() {
  console.log("Start governance deployment process...");
  const timelock = await deployGovernance();
  console.log("Deployment finished!");

  const verificationSuccess = await verifyDeployment(timelock.address);
  if (!verificationSuccess) {
    throw new Error("Deployment verification failed");
  }
  console.log("Verification successful!");
}

main()
  .then(() => console.log("Done."))
  .catch(console.error);
