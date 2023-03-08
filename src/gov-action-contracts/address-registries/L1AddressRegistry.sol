// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./interfaces.sol";

contract L1AddressRegistry is IL1AddressRegistry {
    IInbox public immutable inbox;

    constructor(IInbox _inbox) {
        inbox = _inbox;
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
