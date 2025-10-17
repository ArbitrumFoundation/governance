// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IL2AddressRegistry} from "./../address-registries/L2AddressRegistryInterfaces.sol";
import {L2ArbitrumGovernor} from "./../../L2ArbitrumGovernor.sol";
import {GovernorVotesQuorumFractionUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";

interface IArbTokenPostUpgradeInit {
    function postUpgradeInit(uint256 initialTotalDelegation) external;
}

/// @notice This action is performed as a governance proposal to activate the DVP quorum mechanism.
///         A second proposal (AdjustDvpEstimateAction) is recommended some time later to adjust the initial
///         total delegation estimate set in this proposal.
contract ActivateDvpQuorumAction {
    address public immutable l2AddressRegistry;
    address public immutable arbTokenProxy;
    ProxyAdmin public immutable govProxyAdmin;

    address public immutable newGovernorImpl;
    address public immutable newTokenImpl;

    uint256 public immutable newCoreQuorumNumerator;
    uint256 public immutable coreMinimumQuorum;
    uint256 public immutable coreMaximumQuorum;
    uint256 public immutable newTreasuryQuorumNumerator;
    uint256 public immutable treasuryMinimumQuorum;
    uint256 public immutable treasuryMaximumQuorum;
    uint256 public immutable initialTotalDelegationEstimate;

    constructor(
        address _l2AddressRegistry,
        address _arbTokenProxy,
        ProxyAdmin _govProxyAdmin,
        address _newGovernorImpl,
        address _newTokenImpl,
        uint256 _newCoreQuorumNumerator,
        uint256 _coreMinimumQuorum,
        uint256 _coreMaximumQuorum,
        uint256 _newTreasuryQuorumNumerator,
        uint256 _treasuryMinimumQuorum,
        uint256 _treasuryMaximumQuorum,
        uint256 _initialTotalDelegationEstimate
    ) {
        l2AddressRegistry = _l2AddressRegistry;
        arbTokenProxy = _arbTokenProxy;
        govProxyAdmin = _govProxyAdmin;
        newGovernorImpl = _newGovernorImpl;
        newTokenImpl = _newTokenImpl;
        newCoreQuorumNumerator = _newCoreQuorumNumerator;
        coreMinimumQuorum = _coreMinimumQuorum;
        coreMaximumQuorum = _coreMaximumQuorum;
        newTreasuryQuorumNumerator = _newTreasuryQuorumNumerator;
        treasuryMinimumQuorum = _treasuryMinimumQuorum;
        treasuryMaximumQuorum = _treasuryMaximumQuorum;
        initialTotalDelegationEstimate = _initialTotalDelegationEstimate;
    }

    /// @notice Performs the following:
    ///         1. Upgrades the token contract
    ///         2. Calls postUpgradeInit on the token contract to set the initial total delegation estimate
    ///         3. Upgrades the core governor contract
    ///         4. Sets the new quorum numerator for the core governor
    ///         5. Sets the quorum min/max for the core governor
    ///         6. Upgrades the treasury governor contract
    ///         7. Sets the new quorum numerator for the treasury governor
    ///         8. Sets the quorum min/max for the treasury governor
    function perform() external {
        // 1. Upgrade the token contract
        govProxyAdmin.upgrade(TransparentUpgradeableProxy(payable(arbTokenProxy)), newTokenImpl);

        // 2. Call postUpgradeInit on the token contract
        IArbTokenPostUpgradeInit(arbTokenProxy).postUpgradeInit(initialTotalDelegationEstimate);

        // 3. Upgrade the core governor contract
        address payable coreGov = payable(address(IL2AddressRegistry(l2AddressRegistry).coreGov()));
        govProxyAdmin.upgrade(TransparentUpgradeableProxy(coreGov), newGovernorImpl);

        // 4. Set the new quorum numerator for the core governor
        L2ArbitrumGovernor(coreGov).relay(
            coreGov,
            0,
            abi.encodeCall(
                GovernorVotesQuorumFractionUpgradeable.updateQuorumNumerator,
                (newCoreQuorumNumerator)
            )
        );

        // 5. Set the quorum min/max for the core governor
        L2ArbitrumGovernor(coreGov).relay(
            coreGov,
            0,
            abi.encodeCall(
                L2ArbitrumGovernor.setQuorumMinAndMax, (coreMinimumQuorum, coreMaximumQuorum)
            )
        );

        // 6. Upgrade the treasury governor contract
        address payable treasuryGov =
            payable(address(IL2AddressRegistry(l2AddressRegistry).treasuryGov()));
        govProxyAdmin.upgrade(TransparentUpgradeableProxy(treasuryGov), newGovernorImpl);

        // 7. Set the new quorum numerator for the treasury governor
        L2ArbitrumGovernor(treasuryGov).relay(
            treasuryGov,
            0,
            abi.encodeCall(
                GovernorVotesQuorumFractionUpgradeable.updateQuorumNumerator,
                (newTreasuryQuorumNumerator)
            )
        );

        // 8. Set the quorum min/max for the treasury governor
        L2ArbitrumGovernor(treasuryGov).relay(
            treasuryGov,
            0,
            abi.encodeCall(
                L2ArbitrumGovernor.setQuorumMinAndMax,
                (treasuryMinimumQuorum, treasuryMaximumQuorum)
            )
        );
    }
}
