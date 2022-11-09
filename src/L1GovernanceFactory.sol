// // SPDX-License-Identifier: Apache-2.0
// pragma solidity 0.8.16;

// // import "./L2ArbitrumToken.sol";
// // import "./L2ArbitrumGovernor.sol";
// import "./L1ArbitrumTimelock.sol";
// import "./UpgradeExecutor.sol";

// // @openzeppelin-contracts-upgradeable doesn't contain transparent proxies
// import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
// import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

// /// @title Factory contract that deploys the L1 components for Arbitrum governance
// contract L1GovernanceFactory {
//     event Deployed(L1ArbitrumTimelock timelock, ProxyAdmin proxyAdmin, UpgradeExecutor executor);

//     // CHRIS: TODO: rename all the args to timelock where applicable? or remove them all on the l2 variant
//     function deploy(uint256 _minTimelockDelay, address inbox, address l2Timelock)
//         external
//         returns (L1ArbitrumTimelock timelock, ProxyAdmin proxyAdmin, UpgradeExecutor executor)
//     {
//         proxyAdmin = new ProxyAdmin();

//         timelock = deployTimelock(proxyAdmin);
//         address[] memory proposers;
//         address[] memory executors;
//         timelock.initialize(_minTimelockDelay, proposers, executors, inbox, l2Timelock);

//         // CHRIS: TODO: we need to grant a role for the receiver

//         // CHRIS: TODO: review access control on each of the contracts, and defo the timelocks
//         timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

//         // the timelock itself and deployer are admins
//         timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(this));
//         // CHRIS: TODO: why? we should better explain this
//         // we want the L1 timelock to be able to upgrade itself
//         // timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock));

//         // CHRIS: TODO: do we want upgrades that do both L1 and L2 things at the same time?
//         // CHRIS: TODO: or should these be separate upgrades?
//         // CHRIS: TODO: the l1 upgrade executor should be the owner of the l2 upgrade exector?

//         executor = deployUpgradeExecutor(proxyAdmin);
//         executor.initialize(address(timelock));

//         emit Deployed(timelock, proxyAdmin, executor);

//         // CHRIS: TODO: we should full describe the flow of doing an upgrade somewhere
//     }

//     function deployUpgradeExecutor(ProxyAdmin _proxyAdmin) internal returns (UpgradeExecutor) {
//         address logic = address(new UpgradeExecutor());
//         TransparentUpgradeableProxy proxy =
//             new TransparentUpgradeableProxy(logic, address(_proxyAdmin), bytes(""));
//         return UpgradeExecutor(address(proxy));
//     }

//     function deployTimelock(ProxyAdmin _proxyAdmin)
//         internal
//         returns (L1ArbitrumTimelock timelock)
//     {
//         address logic = address(new L1ArbitrumTimelock());
//         TransparentUpgradeableProxy proxy =
//             new TransparentUpgradeableProxy(logic, address(_proxyAdmin), bytes(""));
//         timelock = L1ArbitrumTimelock(payable(address(proxy)));
//     }
// }
