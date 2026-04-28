// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {L2ArbitrumGovernor} from "src/L2ArbitrumGovernor.sol";
import {L2ArbitrumToken} from "src/L2ArbitrumToken.sol";
import {ActivateDvpQuorumAction} from "src/gov-action-contracts/AIPs/ActivateDvpQuorumAction.sol";

/// @notice Deploys the ActivateDvpQuorumAction contract with the appropriate parameters.
///         Uses CREATE2 for deterministic address and easy verification.
contract DeployActivateDvpQuorumUpgrade is Script{
    function run() external {
        vm.startBroadcast();

        bytes32 salt = bytes32(uint256(1));

        address l2GovernorImpl = address(new L2ArbitrumGovernor{salt: salt}());
        address l2TokenImpl = address(new L2ArbitrumToken{salt: salt}());

        ActivateDvpQuorumAction action = new ActivateDvpQuorumAction{salt: salt}({
            _l2AddressRegistry: 0x56C4E9Eb6c63aCDD19AeC2b1a00e4f0d7aBda9d3,
            _arbTokenProxy: 0x912CE59144191C1204E64559FE8253a0e49E6548,
            _govProxyAdmin: ProxyAdmin(0xdb216562328215E010F819B5aBe947bad4ca961e),
            _newGovernorImpl: l2GovernorImpl,
            _newTokenImpl: l2TokenImpl,
            _newCoreQuorumNumerator: 5000, // denominator is 10_000, so this is 50%
            _coreMinimumQuorum: 150_000_000 ether,
            _coreMaximumQuorum: 450_000_000 ether,
            _newTreasuryQuorumNumerator: 4000, // 40%
            _treasuryMinimumQuorum: 100_000_000 ether,
            _treasuryMaximumQuorum: 300_000_000 ether,
            _initialTotalDelegationEstimate: 5477825566840547165171692750 // include EXCLUDED tokens
        });
        
        console.log("ActivateDvpQuorumAction deployed at:", address(action));

        vm.stopBroadcast();
    }
}