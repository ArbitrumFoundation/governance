// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./interfaces.sol";

contract L1TokenBridgeAddressRegistry is ITokenBridgeAddressRegistry {
    IL1CustomGateway public immutable customGateway;
    IL1GatewayRouter public immutable gatewayRouter;

    constructor(IL1CustomGateway _customGateway, IL1GatewayRouter _gatewayRouter) {
        customGateway = _customGateway;
        gatewayRouter = _gatewayRouter;
    }
}
