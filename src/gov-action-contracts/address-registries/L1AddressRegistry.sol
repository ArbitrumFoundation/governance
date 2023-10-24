// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./interfaces.sol";

contract L1AddressRegistry is IL1AddressRegistry {
    IInbox public immutable inbox;
    IL1Timelock public immutable l1Timelock;
    IL1CustomGateway public immutable customGateway;
    IL1GatewayRouter public immutable gatewayRouter;
    address[] public outboxes;
    address[] public sequencers;

    constructor(
        IInbox _inbox,
        IL1Timelock _l1Timelock,
        IL1CustomGateway _customGateway,
        IL1GatewayRouter _gatewayRouter,
        address[] memory _outboxes,
        address[] memory _sequencers
    ) {
        inbox = _inbox;
        l1Timelock = _l1Timelock;
        customGateway = _customGateway;
        gatewayRouter = _gatewayRouter;
        outboxes = _outboxes;
        sequencers = _sequencers;
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

    function getOutboxes() public view returns (address[] memory) {
        return outboxes;
    }

    function getSequencers() public view returns (address[] memory) {
        return sequencers;
    }
}
