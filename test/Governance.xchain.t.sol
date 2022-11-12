// // SPDX-License-Identifier: Apache-2.0
// pragma solidity 0.8.16;

// import "../src/L1GovernanceFactory.sol";
// import "../src/L2GovernanceFactory.sol";

// import "./util/XChainTest.sol";

// contract GovernanceXChainTest is Test {
//     uint256 initialSupply = 10 * 10 ** 9;
//     uint256 l1TimelockDelay = 10;
//     uint256 l2TimelockDelay = 15;
//     address l1TokenAddr = address(137);
//     address l2TokenLogic = address(123);
//     address l2TimeLockLogic = address(1234);
//     address l2GovernorLogic = address(12_345);
//     address l2UpgradeExecutorLogic = address(123_456);
//     address l2UpgradeExecutorInitialOwner = address(1_234_567);
//     address inbox = address(123_456);

//     L1ArbitrumTimelock l1Timelock;
//     ProxyAdmin l1ProxyAdmin;
//     L2ArbitrumToken l2Token;
//     L2ArbitrumGovernor l2Gov;
//     ArbitrumTimelock l2Timelock;
//     ProxyAdmin l2ProxyAdmin;
//     UpgradeExecutor l2UpgradeExecutor;
//     UpgradeExecutor l1UpgradeExecutor;

//     function testDoesDeployGovernanceContracts() external {
//         // CHRIS: TODO: comment back in

//         // L1GovernanceFactory l1Factory = new L1GovernanceFactory();
//         // L2GovernanceFactory l2Factory = new L2GovernanceFactory();

//         // // no L1 token available yet
//         // (l2Token, l2Gov, l2Timelock, l2ProxyAdmin, l2UpgradeExecutor) = l2Factory.deploy(
//         //     l2TimelockDelay,
//         //     l1TokenAddr,
//         //     l2TokenLogic,
//         //     initialSupply,
//         //     address(this),
//         //     l2TimeLockLogic,
//         //     l2GovernorLogic,
//         //     l2UpgradeExecutorLogic,
//         //     l2UpgradeExecutorInitialOwner
//         // );

//         // (l1Timelock, l1ProxyAdmin, l1UpgradeExecutor) =
//         //     l1Factory.deploy(l1TimelockDelay, inbox, address(l2Timelock), address(l2UpgradeExecutor));

//         // assertGt(address(l2Token).code.length, 0, "no token deployed");
//     }
// }
