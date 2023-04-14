import {
  ArbitrumFoundationVestingWallet__factory,
  L2ArbitrumGovernor__factory,
  L2ArbitrumToken__factory,
} from "../../typechain-types";
import { JsonRpcProvider } from "@ethersproject/providers";
import { BigNumber } from "ethers";
import { getFoundationWalletDeploymentConfig, deployedWallets } from "./config";
import dotenv from "dotenv";
import { assertEquals, assertNumbersEquals, getProxyOwner } from "../testUtils";

dotenv.config();

const { ARB_URL } = process.env;
if (!ARB_URL) throw new Error("ARB_URL required");

const verifyWalletDeployment = async () => {
  const l2Provider = new JsonRpcProvider(ARB_URL);
  const { name: networkName, chainId } = await l2Provider.getNetwork();
  const { beneficiary, startTimestamp, durationSeconds, l2ArbitrumGovernor, l2UpgradeExecutor } =
    getFoundationWalletDeploymentConfig(chainId);
  const arbitrumFoundationWalletAddress = deployedWallets[chainId] as string;

  console.log(
    `Starting verification of wallet ${arbitrumFoundationWalletAddress} on network ${networkName}, ${chainId}`
  );

  const proxyOwner = await getProxyOwner(arbitrumFoundationWalletAddress, l2Provider);
  assertEquals(proxyOwner, l2UpgradeExecutor, "Proxy owner should be L2 UpgradeExecutor");

  const arbitrumFoundationWallet = ArbitrumFoundationVestingWallet__factory.connect(
    arbitrumFoundationWalletAddress,
    l2Provider
  );

  assertEquals(
    await arbitrumFoundationWallet.owner(),
    l2UpgradeExecutor,
    "owner should be L2 UpgradeExecutor"
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
    BigNumber.from(durationSeconds),
    "startTimestamp should be properly set"
  );

  const governor = L2ArbitrumGovernor__factory.connect(l2ArbitrumGovernor, l2Provider);
  const token = L2ArbitrumToken__factory.connect(await governor.token(), l2Provider);
  assertEquals(
    await token.delegates(arbitrumFoundationWalletAddress),
    await governor.EXCLUDE_ADDRESS(),
    "wallet should delegate to exclude address"
  );
  console.log('Successfully verified');
  
};

verifyWalletDeployment().then(()=> console.log("Finished with verification 👍"));

