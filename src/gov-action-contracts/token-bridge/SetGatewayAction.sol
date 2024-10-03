// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "./TokenBridgeActionLib.sol";

contract SetGatewayAction {
    IL1GatewayRouterGetter public immutable addressRegistry;

    constructor(IL1GatewayRouterGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(
        address[] memory _tokens,
        address[] memory _gateways,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable {
        TokenBridgeActionLib.ensureAllContracts(_tokens);
        TokenBridgeActionLib.ensureAllContracts(_gateways);

        addressRegistry.gatewayRouter().setGateways{
            value: _maxGas * _gasPriceBid + _maxSubmissionCost
        }(_tokens, _gateways, _maxGas, _gasPriceBid, _maxSubmissionCost);
    }
}
