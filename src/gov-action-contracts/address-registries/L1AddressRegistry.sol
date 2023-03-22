// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./interfaces.sol";

contract L1AddressRegistry is IL1AddressRegistry {
    IInbox public immutable inbox;
    IL1Timelock public immutable l1Timelock;
    IL1CustomGateway public immutable customGateway;
    IL1GatewayRouter public immutable gatewayRouter;

    constructor(
        IInbox _inbox,
        IL1Timelock _l1Timelock,
        IL1CustomGateway _customGateway,
        IL1GatewayRouter _gatewayRouter
    ) {
        inbox = _inbox;
        l1Timelock = _l1Timelock;
        customGateway = _customGateway;
        gatewayRouter = _gatewayRouter;
    }

    function rollup() public view returns (IRollupCore) {
        return IRollupCore(address(bridge().rollup()));
    }

    function bridge() public view returns (IBridge) {
        return inbox.bridge();
    }

    function sequencerInbox() public view returns (ISequencerInbox) {
        return inbox.sequencerInbox();
    }
}
