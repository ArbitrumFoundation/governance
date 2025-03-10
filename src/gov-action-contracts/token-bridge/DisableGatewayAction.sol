// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "./TokenBridgeActionLib.sol";

/// @notice This action disables gateways for a set of tokens from the L1GatewayRouter
contract DisableGatewayAction {
    IL1GatewayRouterGetter public immutable addressRegistry;

    constructor(IL1GatewayRouterGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(
        address[] memory _tokens,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable {
        TokenBridgeActionLib.ensureAllContracts(_tokens);
        address[] memory _gateways = new address[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            _gateways[i] = address(1); // DISABLED GATEWAY
        }

        addressRegistry.gatewayRouter().setGateways{
            value: _maxGas * _gasPriceBid + _maxSubmissionCost
        }(_tokens, _gateways, _maxGas, _gasPriceBid, _maxSubmissionCost);
    }
}
