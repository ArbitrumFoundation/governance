import {
  ArbitrumFoundationVestingWallet__factory,
  L2ArbitrumGovernor__factory,
  L2ArbitrumToken__factory,
} from "../../typechain-types";
import { JsonRpcProvider } from "@ethersproject/providers";
import { BigNumber } from "ethers";
import { getFoundationWalletDeploymentConfig, deployedWallets } from "./config";
import dotenv from "dotenv";
import { assertEquals, assertNumbersEquals, getProxyOwner, getProxyImplementation } from "../testUtils";
import {  ContractVerifier } from "../contractVerifier";
dotenv.config();

const { ARB_URL, ARBISCAN_API_KEY } = process.env;
if (!ARB_URL) throw new Error("ARB_URL required");
if (!ARBISCAN_API_KEY) throw new Error("ARBISCAN_API_KEY required");


const verifyWalletDeployment = async () => {
  const l2Provider = new JsonRpcProvider(ARB_URL);
  const { name: networkName, chainId } = await l2Provider.getNetwork();
  const verifier = new ContractVerifier(chainId, ARBISCAN_API_KEY, {} )
  const { beneficiary, startTimestamp, vestingPeriodInSeconds, l2ArbitrumGovernor, l2GovProxyAdmin } =
    getFoundationWalletDeploymentConfig(chainId);
  const arbitrumFoundationWalletAddress = deployedWallets[chainId] as string;
  console.log(
    `Starting verification of wallet ${arbitrumFoundationWalletAddress} on network ${networkName}, ${chainId}`
  );

  const implementation = await getProxyImplementation(arbitrumFoundationWalletAddress, l2Provider);
  await verifier.verifyWithAddress("ArbitrumFoundationVestingWalletProxy", arbitrumFoundationWalletAddress);
  await verifier.verifyWithAddress("ArbitrumFoundationVestingWalletLogic", implementation);

  const proxyOwner = await getProxyOwner(arbitrumFoundationWalletAddress, l2Provider);
  assertEquals(proxyOwner, l2GovProxyAdmin, "Proxy owner should be L2 l2GovProxyAdmin");

  const arbitrumFoundationWallet = ArbitrumFoundationVestingWallet__factory.connect(
    arbitrumFoundationWalletAddress,
    l2Provider
  );

  assertEquals(
    await arbitrumFoundationWallet.beneficiary(),
    beneficiary,
    "beneficiary should be properly set"
  );

  assertNumbersEquals(
    await arbitrumFoundationWallet.start(),
    BigNumber.from(startTimestamp),
    "startTimestamp should be properly set"
  );

  assertNumbersEquals(
    await arbitrumFoundationWallet.duration(),
    BigNumber.from(vestingPeriodInSeconds),
    "startTimestamp should be properly set"
  );

  const governor = L2ArbitrumGovernor__factory.connect(l2ArbitrumGovernor, l2Provider);
  assertEquals(
    await arbitrumFoundationWallet.owner(),
    await governor.owner(),
    "owner should be same owner as gov (L2 UpgradeExecutor)"
  );
  const token = L2ArbitrumToken__factory.connect(await governor.token(), l2Provider);
  assertEquals(
    await token.delegates(arbitrumFoundationWalletAddress),
    await governor.EXCLUDE_ADDRESS(),
    "wallet should delegate to exclude address"
  );
  console.log('Successfully verified');
  
};

verifyWalletDeployment().then(()=> console.log("Finished with verification 👍"));

