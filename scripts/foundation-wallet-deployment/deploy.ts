import {
  ArbitrumFoundationVestingWallet__factory,
  TransparentUpgradeableProxy__factory,
} from "../../typechain-types";
import { JsonRpcProvider } from "@ethersproject/providers";
import { Wallet, constants, utils } from "ethers";
import { getFoundationWalletDeploymentConfig } from "./config";
import dotenv from "dotenv";
dotenv.config();

const { ARB_URL, ARB_KEY } = process.env;
if (!ARB_URL) throw new Error("ARB_URL required");
if (!ARB_KEY) throw new Error("ARB_KEY required");

const deployWallet = async () => {
  const l2Provider = new JsonRpcProvider(ARB_URL);
  const deployer = new Wallet(ARB_KEY, l2Provider);

  if ((await deployer.getBalance()).eq(constants.Zero))
    throw new Error(`${deployer.address} needs funds`);

  const { name: networkName, chainId } = await l2Provider.getNetwork();
  const {
    beneficiary,
    startTimestamp,
    vestingPeriodInSeconds,
    l2ArbitrumGovernor,
    l2GovProxyAdmin,
  } = getFoundationWalletDeploymentConfig(chainId);
  if (chainId === 42161){
    await ensureContract(beneficiary, l2Provider); // for mainnet this will def be a multisig; for testnet it can be lax
  }
  await ensureContract(l2ArbitrumGovernor, l2Provider);
  await ensureContract(l2GovProxyAdmin, l2Provider);
  if (startTimestamp === 0) throw new Error("need startTimestamp");
  if (vestingPeriodInSeconds === 0) throw new Error("need vestingPeriodInSeconds");

  console.log(
    `Starting deployment from deployer ${deployer.address} on network ${networkName}, ${chainId}`
  );

  const arbitrumFoundationVestingWalletLogic = await new ArbitrumFoundationVestingWallet__factory(
    deployer
  ).deploy();
  await arbitrumFoundationVestingWalletLogic.deployed();
  console.log(
    `ArbitrumFoundationVestingWallet Logic deployed at ${arbitrumFoundationVestingWalletLogic.address}`
  );

  const arbitrumFoundationVestingWalletProxy = await new TransparentUpgradeableProxy__factory(
    deployer
  ).deploy(arbitrumFoundationVestingWalletLogic.address, l2GovProxyAdmin, "0x");

  await arbitrumFoundationVestingWalletProxy.deployed();

  console.log(
    `ArbitrumFoundationVestingWallet Proxy deployed at ${arbitrumFoundationVestingWalletProxy.address}`
  );

  const arbitrumFoundationVestingWallet = ArbitrumFoundationVestingWallet__factory.connect(
    arbitrumFoundationVestingWalletProxy.address,
    deployer
  );

  const res = await arbitrumFoundationVestingWallet.initialize(
    beneficiary,
    startTimestamp,
    vestingPeriodInSeconds,
    l2ArbitrumGovernor
  );

  await res.wait();

  console.log("Successfully initialized");
  return;
};

const ensureContract = async (address: string, provider: JsonRpcProvider) => {
  if(!address) throw new Error(`Address not provided`);
  if (!utils.isAddress(address)) throw new Error(`Invalid address: ${address}`);
  if ((await provider.getCode(address)).length <= 2)
    throw new Error(`${address} contract not found`);
};

deployWallet().then(() => console.log("Finished with deployment 👍"));
