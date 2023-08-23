import { Wallet, ethers } from "ethers";
import { L2ArbitrumToken__factory, L2SecurityCouncilMgmtFactory__factory, SecurityCouncilManager__factory, SecurityCouncilMemberElectionGovernor__factory, SecurityCouncilMemberRemovalGovernor__factory, SecurityCouncilNomineeElectionGovernor__factory } from "../../typechain-types";
import { DeployParamsStruct } from "../../typechain-types/src/security-council-mgmt/factories/L2SecurityCouncilMgmtFactory";
import { TransparentUpgradeableProxy__factory } from "@arbitrum/sdk/dist/lib/abi/factories/TransparentUpgradeableProxy__factory";
import { getNamedObjectItems } from "./utils";
import dotenv from "dotenv";
dotenv.config();

// env vars:
// RPC_URL (optional, defaults to http://localhost:8545)
// PRIVATE_KEY

type DeployParamsPartial = Omit<
  DeployParamsStruct,
  "govChainEmergencySecurityCouncil" |
  "l2CoreGovTimelock" |
  "govChainProxyAdmin" |
  "arbToken" |
  "l1ArbitrumTimelock" |
  "l2UpgradeExecutor" |
  "firstNominationStartDate" |
  "securityCouncils" |
  "upgradeExecutors"
>;

const zxDead = "0x000000000000000000000000000000000000dead";

const partialDeployParams: DeployParamsPartial = {
  secondCohort: [
    "0x0000000000000000000000000000000000000001",
    "0x0000000000000000000000000000000000000002",
    "0x0000000000000000000000000000000000000003",
    "0x0000000000000000000000000000000000000004",
    "0x0000000000000000000000000000000000000005",
    "0x0000000000000000000000000000000000000006",
  ],
  firstCohort: [
    "0x000000000000000000000000000000000000000a",
    "0x000000000000000000000000000000000000000b",
    "0x000000000000000000000000000000000000000c",
    "0x000000000000000000000000000000000000000d",
    "0x000000000000000000000000000000000000000e",
    "0x000000000000000000000000000000000000000f",
  ],
  l1TimelockMinDelay: 0,
  removalGovVotingDelay: 0,
  removalGovVotingPeriod: minutes(5 * 60),
  removalGovQuorumNumerator: 1000, // 10%
  removalGovProposalThreshold: ethers.utils.parseEther("1000000"), // 1 million tokens
  removalGovVoteSuccessNumerator: 8333, // todo: check this
  removalGovMinPeriodAfterQuorum: minutes(60),
  removalProposalExpirationBlocks: 100, // number of blocks after which a successful removal proposal expires
  nomineeVettingDuration: minutes(60),
  nomineeVetter: "0x000000000000000000000000000000000000dead",
  nomineeQuorumNumerator: 20, // 0.2%
  nomineeVotingPeriod: minutes(5 * 60),
  memberVotingPeriod: minutes(5 * 60),
  fullWeightDuration: minutes(60),
}

// convert minutes to blocks
function minutes(n: number) {
  return Math.round(n * 60 / 12); // divide by 12 because 1 block per 12 seconds
}

async function deployBytecode(signer: Wallet, bytecode: string) {
  const contract = await new ethers.ContractFactory([], bytecode, signer).deploy();
  await contract.deployed();
  return contract;
}

function deployNoopContract(signer: Wallet) {
  return deployBytecode(signer, "60088060093d393df360015f5260205ff3");
}

function deployDummyGnosisSafe(signer: Wallet) {
  const bytecode = "608060405234801561001057600080fd5b50610154806100206000396000f3fe608060405234801561001057600080fd5b50600436106100365760003560e01c80632f54bf6e1461003b578063a0e67e2b14610064575b600080fd5b61004f6100493660046100a1565b50600190565b60405190151581526020015b60405180910390f35b61006c610079565b60405161005b91906100d1565b60408051600c8082526101a08201909252606091602082016101808036833701905050905090565b6000602082840312156100b357600080fd5b81356001600160a01b03811681146100ca57600080fd5b9392505050565b6020808252825182820181905260009190848201906040850190845b818110156101125783516001600160a01b0316835292840192918401916001016100ed565b5090969550505050505056fea26469706673582212200450c5c9306adc3deb1c0f327c8ca37c917cad674222ad7536b032eb3c0c3e5c64736f6c63430008100033";
  return deployBytecode(signer, bytecode);
}

async function deployToken(signer: Wallet) {
  const impl = await new L2ArbitrumToken__factory(signer).deploy();
  await impl.deployed();

  const proxy = await new TransparentUpgradeableProxy__factory(signer).deploy(impl.address, zxDead, "0x");
  await proxy.deployed();

  const token = L2ArbitrumToken__factory.connect(proxy.address, signer);
  await (await token.initialize(zxDead, ethers.utils.parseEther("10000000000"), signer.address)).wait();

  return token;
}

function makeStartDateStruct(startDate: Date) {
  return {
    year: startDate.getUTCFullYear(),
    month: startDate.getUTCMonth() + 1,
    day: startDate.getUTCDate(),
    hour: startDate.getUTCHours(),
  }
}

async function makeFullDeployParams(partialDeployParams: DeployParamsPartial, signer: Wallet): Promise<DeployParamsStruct> {
  const noop = await deployNoopContract(signer);
  const gnosisSafe = await deployDummyGnosisSafe(signer);

  const date = new Date(new Date().getTime() + 60 * 60 * 1000); // add 1 hour to the current time

  return {
    ...partialDeployParams,
    govChainEmergencySecurityCouncil: gnosisSafe.address,
    l2CoreGovTimelock: noop.address,
    govChainProxyAdmin: noop.address,
    arbToken: (await deployToken(signer)).address,
    l1ArbitrumTimelock: noop.address,
    l2UpgradeExecutor: noop.address,
    firstNominationStartDate: makeStartDateStruct(date),
    securityCouncils: [],
    upgradeExecutors: [],
  }
}

async function deployImplementationsForFactory(signer: Wallet) {
  const nomineeElectionGovernor = await new SecurityCouncilNomineeElectionGovernor__factory(signer).deploy();
  await nomineeElectionGovernor.deployed();

  const memberElectionGovernor = await new SecurityCouncilMemberElectionGovernor__factory(signer).deploy();
  await memberElectionGovernor.deployed();

  const securityCouncilManager = await new SecurityCouncilManager__factory(signer).deploy();
  await securityCouncilManager.deployed();

  const securityCouncilMemberRemoverGov = await new SecurityCouncilMemberRemovalGovernor__factory(signer).deploy();
  await securityCouncilMemberRemoverGov.deployed();

  return {
    nomineeElectionGovernor: nomineeElectionGovernor.address,
    memberElectionGovernor: memberElectionGovernor.address,
    securityCouncilManager: securityCouncilManager.address,
    securityCouncilMemberRemoverGov: securityCouncilMemberRemoverGov.address,
  }
}

async function main() {
  if (!process.env.PRIVATE_KEY) throw new Error("need PRIVATE_KEY");

  console.log("RPC_URL:", process.env.RPC_URL || "http://localhost:8545");

  const signer = new ethers.Wallet(process.env.PRIVATE_KEY, new ethers.providers.JsonRpcProvider(process.env.RPC_URL));

  const implementations = await deployImplementationsForFactory(signer);

  // deploy the actual factory contract
  const factory = await new L2SecurityCouncilMgmtFactory__factory(signer).deploy();
  await factory.deployed();

  // make full deploy params
  const fullDeployParams = await makeFullDeployParams(partialDeployParams, signer);

  // call the factory's deploy function
  const deployTx = await factory.deploy(
    fullDeployParams,
    implementations,
  );

  const deployReceipt = await deployTx.wait();

  // get ContractsDeployed event
  const event = deployReceipt.events?.find((e) => e.event === "ContractsDeployed");

  const namedItems = getNamedObjectItems(event?.args?.deployedContracts);

  console.log({
    ...namedItems,
    arbToken: fullDeployParams.arbToken,
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
