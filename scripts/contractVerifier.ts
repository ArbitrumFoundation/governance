import { exec } from "child_process";
import { ethers } from "ethers";
import { DeployerConfig } from "./deployerConfig";
import { DeployProgressCache } from "./providerSetup";

export class ContractVerifier {
  verifyCommand: string;

  chainId: number;
  apiKey: string = "";
  deployedContracts: DeployProgressCache;

  readonly NUM_OF_OPTIMIZATIONS = 20000;
  readonly COMPILER_VERSION = "0.8.16";

  ///// List of contract addresses and their corresponding source code files
  readonly TUP =
    "node_modules/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy";
  readonly PROXY_ADMIN =
    "node_modules/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin";
  readonly EXECUTOR = "src/UpgradeExecutor.sol:UpgradeExecutor";

  readonly contractToSource = {
    l1UpgradeExecutorLogic: "src/UpgradeExecutor.sol:UpgradeExecutor",
    l2TimelockLogic: "src/ArbitrumTimelock.sol:ArbitrumTimelock",
    l2GovernorLogic: "src/L2ArbitrumGovernor.sol:L2ArbitrumGovernor",
    l2FixedDelegateLogic: "src/FixedDelegateErc20Wallet.sol:FixedDelegateErc20Wallet",
    l2TokenLogic: "src/L2ArbitrumToken.sol:L2ArbitrumToken",
    l2UpgradeExecutorLogic: this.EXECUTOR,
    l1GovernanceFactory: "src/L1GovernanceFactory.sol:L1GovernanceFactory",
    l2GovernanceFactory: "src/L2GovernanceFactory.sol:L2GovernanceFactory",
    l1ReverseCustomGatewayLogic:
      "token-bridge-contracts/contracts/tokenbridge/ethereum/gateway/L1ForceOnlyReverseCustomGateway.sol:L1ForceOnlyReverseCustomGateway",
    l1ReverseCustomGatewayProxy: this.TUP,
    l2ReverseCustomGatewayLogic:
      "token-bridge-contracts/contracts/tokenbridge/arbitrum/gateway/L2ReverseCustomGateway.sol:L2ReverseCustomGateway",
    l2ReverseCustomGatewayProxy: this.TUP,
    l1TokenLogic: "src/L1ArbitrumToken.sol:L1ArbitrumToken",
    l1TokenProxy: this.TUP,
    novaProxyAdmin: this.PROXY_ADMIN,
    novaUpgradeExecutorLogic: this.EXECUTOR,
    novaUpgradeExecutorProxy: this.TUP,
    novaTokenLogic:
      "token-bridge-contracts/contracts/tokenbridge/libraries/L2CustomGatewayToken.sol:L2CustomGatewayToken",
    novaTokenProxy: this.TUP,
    l2CoreGoverner: this.TUP,
    l2CoreTimelock: this.TUP,
    l2TreasuryTimelock: this.TUP,
    l2Executor: this.TUP,
    l2ProxyAdmin: this.PROXY_ADMIN,
    l2Token: this.TUP,
    l2TreasuryGoverner: this.TUP,
    l2ArbTreasury: this.TUP,
    arbitrumDAOConstitution: "src/ArbitrumDAOConstitution.sol:ArbitrumDAOConstitution",
    l1Executor: this.TUP,
    l1ProxyAdmin: this.PROXY_ADMIN,
    l1TimelockLogic: "src/L1ArbitrumTimelock.sol:L1ArbitrumTimelock",
    l1Timelock: this.TUP,
    vestedWalletFactory: "src/ArbitrumVestingWalletFactory.sol:ArbitrumVestingWalletsFactory",
    l2TokenDistributor: "src/TokenDistributor.sol:TokenDistributor",
    noteStore: "src/hardhatTest/TestUpgrade.sol:NoteStore",
    testUpgrade: "src/hardhatTest/TestUpgrade.sol:TestUpgrade",
    L1AddressRegistry: "src/gov-action-contracts/address-registries/L1AddressRegistry.sol:L1AddressRegistry",
    L1SetInitialGovParamsAction: "src/gov-action-contracts/goerli/L1SetInitialGovParamsAction.sol:L1SetInitialGovParamsAction",
    L2AddressRegistry: "src/gov-action-contracts/address-registries/L2AddressRegistry.sol:L2AddressRegistry",
    ArbGoerliSetInitialGovParamsAction: "src/gov-action-contracts/goerli/ArbGoerliSetInitialGovParamsAction.sol:ArbGoerliSetInitialGovParamsAction",
    AIP1Point2Action: "src/gov-action-contracts/AIPs/AIP1Point2Action.sol:AIP1Point2Action",
    AIP4Action: "src/gov-action-contracts/AIPs/AIP4Action.sol:AIP4Action",
    SetSweepReceiverAction: "src/gov-action-contracts/AIPs/AIP7/SetSweepReceiverAction.sol:SetSweepReceiverAction",
    UpdateGasChargeAction: "src/gov-action-contracts/AIPs/AIP7/UpdateGasChargeAction.sol:UpdateGasChargeAction",
    UpdateL1CoreTimelockAction: "src/gov-action-contracts/AIPs/AIP7/UpdateL1CoreTimelockAction.sol:UpdateL1CoreTimelockAction",
    ArbitrumFoundationVestingWalletProxy: this.TUP,
    ArbitrumFoundationVestingWalletLogic: "src/ArbitrumFoundationVestingWallet.sol:ArbitrumFoundationVestingWallet",
    AddNovaKeysetAction: "src/gov-action-contracts/nonemergency/AddNovaKeysetAction.sol:AddNovaKeysetAction",
  };

  constructor(chainId: number, apiKey: string, deployedContracts: DeployProgressCache) {
    this.chainId = chainId;
    this.deployedContracts = deployedContracts;
    if (apiKey) {
      this.apiKey = apiKey;
    }
    this.verifyCommand = `forge verify-contract --chain-id ${chainId} --num-of-optimizations ${this.NUM_OF_OPTIMIZATIONS} --compiler-version ${this.COMPILER_VERSION}`;
  }

  async verify(name: keyof typeof this.contractToSource, constructorArgs?: string) {
    const contractAddress = this.deployedContracts[name as keyof DeployProgressCache] as string;
    if (!contractAddress) {
      console.log(name, " not found");
    }

    await this.verifyWithAddress(name, contractAddress, constructorArgs);
  }

  async verifyWithAddress(name: keyof typeof this.contractToSource, contractAddress: string, constructorArgs?: string) {
    // avoid rate limiting
    await new Promise((resolve) => setTimeout(resolve, 1000));

    const sourceFile = this.contractToSource[name];

    let command = this.verifyCommand;
    if (constructorArgs) {
      command = `${command} --constructor-args ${constructorArgs}`;
    }
    command = `${command} ${contractAddress} ${sourceFile} --etherscan-api-key ${this.apiKey}`;

    exec(command, (err: Error | null, stdout: string, stderr: string) => {
      console.log("-----------------");
      console.log(command);
      if (err) {
        console.log("Failed to submit for verification", contractAddress, stderr);
      } else {
        console.log("Successfully submitted for verification", contractAddress);
        console.log(stdout);
      }
    });
  }

  async verifyArbContracts(config: DeployerConfig, arbDeployer: string) {
    console.log("Verify Arbitrum contracts");

    const abi = ethers.utils.defaultAbiCoder;

    await this.verify("l2TimelockLogic");
    await this.verify("l2GovernorLogic");
    await this.verify("l2FixedDelegateLogic");
    await this.verify("l2TokenLogic");
    await this.verify("l2UpgradeExecutorLogic");
    await this.verify(
      "l2GovernanceFactory",
      abi.encode(
        ["address", "address", "address", "address", "address", "address", "address"],
        [
          this.deployedContracts.l2TimelockLogic!,
          this.deployedContracts.l2GovernorLogic!,
          this.deployedContracts.l2TimelockLogic!,
          this.deployedContracts.l2FixedDelegateLogic!,
          this.deployedContracts.l2GovernorLogic!,
          this.deployedContracts.l2TokenLogic!,
          this.deployedContracts.l2UpgradeExecutorLogic!,
        ]
      )
    );
    await this.verify("l2ReverseCustomGatewayLogic");
    await this.verify(
      "l2ReverseCustomGatewayProxy",
      abi.encode(
        ["address", "address", "bytes"],
        [
          this.deployedContracts.l2ReverseCustomGatewayProxy!,
          this.deployedContracts.l2ProxyAdmin!,
          "0x",
        ]
      )
    );
    await this.verify(
      "l2CoreGoverner",
      abi.encode(
        ["address", "address", "bytes"],
        [this.deployedContracts.l2GovernorLogic!, this.deployedContracts.l2ProxyAdmin!, "0x"]
      )
    );
    await this.verify(
      "l2CoreTimelock",
      abi.encode(
        ["address", "address", "bytes"],
        [this.deployedContracts.l2TimelockLogic!, this.deployedContracts.l2ProxyAdmin!, "0x"]
      )
    );
    await this.verify(
      "l2Executor",
      abi.encode(
        ["address", "address", "bytes"],
        [this.deployedContracts.l2UpgradeExecutorLogic!, this.deployedContracts.l2ProxyAdmin!, "0x"]
      )
    );
    await this.verify("l2ProxyAdmin");
    await this.verify(
      "l2Token",
      abi.encode(
        ["address", "address", "bytes"],
        [this.deployedContracts.l2TokenLogic!, this.deployedContracts.l2ProxyAdmin!, "0x"]
      )
    );
    await this.verify(
      "l2TreasuryGoverner",
      abi.encode(
        ["address", "address", "bytes"],
        [this.deployedContracts.l2GovernorLogic!, this.deployedContracts.l2ProxyAdmin!, "0x"]
      )
    );
    await this.verify(
      "l2TreasuryTimelock",
      abi.encode(
        ["address", "address", "bytes"],
        [this.deployedContracts.l2TimelockLogic!, this.deployedContracts.l2ProxyAdmin!, "0x"]
      )
    );
    this.verify(
      "l2ArbTreasury",
      abi.encode(
        ["address", "address", "bytes"],
        [this.deployedContracts.l2FixedDelegateLogic!, this.deployedContracts.l2ProxyAdmin!, "0x"]
      )
    );
    await this.verify(
      "arbitrumDAOConstitution",
      abi.encode(["bytes32"], [config.ARBITRUM_DAO_CONSTITUTION_HASH])
    );
    await this.verify("vestedWalletFactory");
    await this.verify(
      "l2TokenDistributor",
      abi.encode(
        ["address", "address", "address", "uint256", "uint256", "address"],
        [
          this.deployedContracts.l2Token!,
          this.deployedContracts.l2TreasuryTimelock!,
          arbDeployer,
          config.L2_CLAIM_PERIOD_START,
          config.L2_CLAIM_PERIOD_END,
          "0x00000000000000000000000000000000000A4B86",
        ]
      )
    );
  }

  async verifyEthContracts() {
    console.log("Verify Ethereum contracts");

    const abi = ethers.utils.defaultAbiCoder;

    await this.verify("l1UpgradeExecutorLogic");
    await this.verify(
      "l1Executor",
      abi.encode(
        ["address", "address", "bytes"],
        [this.deployedContracts.l1UpgradeExecutorLogic!, this.deployedContracts.l1ProxyAdmin!, "0x"]
      )
    );
    await this.verify("l1GovernanceFactory");
    await this.verify("l1ReverseCustomGatewayLogic");
    await this.verify(
      "l1ReverseCustomGatewayProxy",
      abi.encode(
        ["address", "address", "bytes"],
        [
          this.deployedContracts.l1ReverseCustomGatewayLogic!,
          this.deployedContracts.l1ProxyAdmin!,
          "0x",
        ]
      )
    );
    await this.verify("l1TokenLogic");
    await this.verify(
      "l1TokenProxy",
      abi.encode(
        ["address", "address", "bytes"],
        [this.deployedContracts.l1TokenLogic!, this.deployedContracts.l1ProxyAdmin!, "0x"]
      )
    );
    await this.verify("l1ProxyAdmin");
    await this.verify(
      "l1Timelock",
      abi.encode(
        ["address", "address", "bytes"],
        [this.deployedContracts.l1Timelock, this.deployedContracts.l1ProxyAdmin, "0x"]
      )
    );
  }

  async verifyNovaContracts() {
    console.log("Verify Nova contracts");
    const abi = ethers.utils.defaultAbiCoder;

    await this.verify("novaProxyAdmin");
    await this.verify("novaUpgradeExecutorLogic");
    await this.verify(
      "novaUpgradeExecutorProxy",
      abi.encode(
        ["address", "address", "bytes"],
        [
          this.deployedContracts.novaUpgradeExecutorLogic!,
          this.deployedContracts.novaProxyAdmin!,
          "",
        ]
      )
    );
    await this.verify("novaTokenLogic");
    await this.verify(
      "novaTokenProxy",
      abi.encode(
        ["address", "address", "bytes"],
        [this.deployedContracts.novaTokenLogic!, this.deployedContracts.novaProxyAdmin!, "0x"]
      )
    );
  }
}
