// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "./TokenBridgeActionLib.sol";

contract RegisterL2TokenInArbCustomGatewayAction {
    IL1CustomGatewayGetter public immutable addressRegistry;

    constructor(IL1CustomGatewayGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(
        address[] memory _l1Tokens,
        address[] memory _l2Tokens,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable {
        TokenBridgeActionLib.ensureAllContracts(_l1Tokens);

        addressRegistry.customGateway().forceRegisterTokenToL2{
            value: _maxGas * _gasPriceBid + _maxSubmissionCost
        }(_l1Tokens, _l2Tokens, _maxGas, _gasPriceBid, _maxSubmissionCost);
    }
}
