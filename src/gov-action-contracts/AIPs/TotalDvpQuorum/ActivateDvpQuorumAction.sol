// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IL2AddressRegistry} from "../../address-registries/L2AddressRegistryInterfaces.sol";
import {L2ArbitrumToken} from "../../../L2ArbitrumToken.sol";
import {
    L2ArbitrumGovernor,
    GovernorVotesQuorumFractionUpgradeable
} from "../../../L2ArbitrumGovernor.sol";

/// @notice Activates DVP based quorum. The ARB token contract must already be tracking total DVP delta checkpoints.
contract ActivateDvpQuorumAction {
    address public immutable l2AddressRegistry;
    address public immutable l2ArbitrumToken;
    address public immutable govProxyAdmin;
    address public immutable newGovernorImpl;
    uint256 public immutable coreQuorumNumerator;
    uint256 public immutable treasuryQuorumNumerator;
    uint256 public immutable totalDelegationAnchor;

    constructor(
        address _l2AddressRegistry,
        address _l2ArbitrumToken,
        address _govProxyAdmin,
        address _newGovernorImpl,
        uint256 _coreQuorumNumerator,
        uint256 _treasuryQuorumNumerator,
        uint256 _totalDelegationAnchor
    ) {
        l2AddressRegistry = _l2AddressRegistry;
        l2ArbitrumToken = _l2ArbitrumToken;
        govProxyAdmin = _govProxyAdmin;
        newGovernorImpl = _newGovernorImpl;
        coreQuorumNumerator = _coreQuorumNumerator;
        treasuryQuorumNumerator = _treasuryQuorumNumerator;
        totalDelegationAnchor = _totalDelegationAnchor;
    }

    /// @notice Performs the following:
    ///         - Sets the total delegation anchor in the ARB token
    ///         - Upgrades the core and treasury governor
    ///         - Sets the new quorum numerator in both governors
    function perform() external {
        // set the total delegation anchor in the ARB token
        L2ArbitrumToken(l2ArbitrumToken).setTotalDelegationAnchor(totalDelegationAnchor);

        // upgrade the core governor
        address payable coreGovProxy =
            payable(address(IL2AddressRegistry(l2AddressRegistry).coreGov()));
        ProxyAdmin(govProxyAdmin).upgrade(
            TransparentUpgradeableProxy(coreGovProxy), newGovernorImpl
        );

        // upgrade the treasury governor
        address payable treasuryGovProxy =
            payable(address(IL2AddressRegistry(l2AddressRegistry).treasuryGov()));
        ProxyAdmin(govProxyAdmin).upgrade(
            TransparentUpgradeableProxy(treasuryGovProxy), newGovernorImpl
        );

        // set the new quorum numerator in both governors
        L2ArbitrumGovernor(coreGovProxy).relay(
            coreGovProxy,
            0,
            abi.encodeCall(
                GovernorVotesQuorumFractionUpgradeable.updateQuorumNumerator, (coreQuorumNumerator)
            )
        );
        L2ArbitrumGovernor(treasuryGovProxy).relay(
            treasuryGovProxy,
            0,
            abi.encodeCall(
                GovernorVotesQuorumFractionUpgradeable.updateQuorumNumerator,
                (treasuryQuorumNumerator)
            )
        );
    }
}
