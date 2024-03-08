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

const START_DATE = new Date(new Date().getTime() + 60 * 60 * 1000); // 1 hour from now, there must be at least an hour delay or deployment will fail

// i.e. votingDelay
const addContenderDuration = minutes(5 * 60)

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

function deployCallRelayer(signer: Wallet) {
  return deployBytecode(signer, "0x608060405234801561001057600080fd5b506102ac806100206000396000f3fe60806040526004361061001e5760003560e01c80631b8b921d14610042575b60408051600160208083019190915282518083038201815291830190925280519101f35b610055610050366004610133565b610057565b005b600080836001600160a01b031634846040516100739190610227565b60006040518083038185875af1925050503d80600081146100b0576040519150601f19603f3d011682016040523d82523d6000602084013e6100b5565b606091505b50915091508181516000146100ca57816100ef565b6040518060400160405280600b81526020016a10d85b1b0819985a5b195960aa1b8152505b906101165760405162461bcd60e51b815260040161010d9190610243565b60405180910390fd5b5050505050565b634e487b7160e01b600052604160045260246000fd5b6000806040838503121561014657600080fd5b82356001600160a01b038116811461015d57600080fd5b9150602083013567ffffffffffffffff8082111561017a57600080fd5b818501915085601f83011261018e57600080fd5b8135818111156101a0576101a061011d565b604051601f8201601f19908116603f011681019083821181831017156101c8576101c861011d565b816040528281528860208487010111156101e157600080fd5b8260208601602083013760006020848301015280955050505050509250929050565b60005b8381101561021e578181015183820152602001610206565b50506000910152565b60008251610239818460208701610203565b9190910192915050565b6020815260008251806020840152610262816040850160208701610203565b601f01601f1916919091016040019291505056fea2646970667358221220dca9e5ce7ee1c6ca348560fef97282b3e924eb88b7133b67eafbb59349cda2bb64736f6c63430008150033");
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
  const callRelayer = await deployCallRelayer(signer);
  const noop = await deployNoopContract(signer);
  const gnosisSafe = await deployDummyGnosisSafe(signer);

  return {
    ...partialDeployParams,
    govChainEmergencySecurityCouncil: gnosisSafe.address,
    l2CoreGovTimelock: noop.address,
    govChainProxyAdmin: noop.address,
    arbToken: (await deployToken(signer)).address,
    l1ArbitrumTimelock: noop.address,
    l2UpgradeExecutor: callRelayer.address,
    firstNominationStartDate: makeStartDateStruct(START_DATE),
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

  const namedItems = getNamedObjectItems(event?.args?.deployedContracts) as any;
  
  // set the votingDelay
  const govIface = SecurityCouncilNomineeElectionGovernor__factory.createInterface();
  const relayCalldata = govIface.encodeFunctionData('relay', [
    namedItems.nomineeElectionGovernor,
    0,
    govIface.encodeFunctionData("setVotingDelay", [addContenderDuration]),
  ])
  // 0x1b8b921d is the selector for callRelayer.call(address, bytes)
  const callRelayerCalldata = ethers.utils.concat(['0x1b8b921d', new ethers.utils.AbiCoder().encode(['address', 'bytes'], [namedItems.nomineeElectionGovernor, relayCalldata])])
  await (await signer.sendTransaction({ to: fullDeployParams.l2UpgradeExecutor, data: callRelayerCalldata })).wait();

  
  console.log({
    ...namedItems,
    arbToken: fullDeployParams.arbToken,
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
