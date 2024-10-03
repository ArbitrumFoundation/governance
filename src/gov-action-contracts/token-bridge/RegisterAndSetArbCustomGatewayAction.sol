// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "./TokenBridgeActionLib.sol";

contract RegisterAndSetArbCustomGatewayAction {
    IL1AddressRegistry public immutable addressRegistry;

    constructor(IL1AddressRegistry _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(
        address[] memory _l1Tokens,
        address[] memory _l2Tokens,
        uint256 _maxGasForRegister,
        uint256 _gasPriceBidForRegister,
        uint256 _maxSubmissionCostForRegister,
        uint256 _maxGasForSetGateway,
        uint256 _gasPriceBidForSetGateway,
        uint256 _maxSubmissionCostForSetGateway
    ) external payable {
        TokenBridgeActionLib.ensureAllContracts(_l1Tokens);

        IL1CustomGateway customGateway = addressRegistry.customGateway();

        customGateway.forceRegisterTokenToL2{
            value: _maxGasForRegister * _gasPriceBidForRegister + _maxSubmissionCostForRegister
        }(
            _l1Tokens,
            _l2Tokens,
            _maxGasForRegister,
            _gasPriceBidForRegister,
            _maxSubmissionCostForRegister
        );

        address[] memory gateways = new address[](_l1Tokens.length);
        for (uint256 i = 0; i < _l1Tokens.length; i++) {
            gateways[i] = address(customGateway);
        }
        addressRegistry.gatewayRouter().setGateways{
            value: _maxGasForSetGateway * _gasPriceBidForSetGateway + _maxSubmissionCostForSetGateway
        }(
            _l1Tokens,
            gateways,
            _maxGasForSetGateway,
            _gasPriceBidForSetGateway,
            _maxSubmissionCostForSetGateway
        );
    }
}
