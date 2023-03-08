// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/bridge/IBridge.sol";
import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/ISequencerInbox.sol";

interface IRollupCore {
    function pause() external;
    function resume() external;
    function forceResolveChallenge(address[] memory stackerA, address[] memory stackerB) external;
    function outbox() external view returns (IOutbox);
    function setOutbox(IOutbox _outbox) external;
}

interface IRollupGetter {
    function rollup() external view returns (IRollupCore);
}

interface IBridgeGetter {
    function bridge() external view returns (IBridge);
}

interface IInboxGetter {
    function inbox() external view returns (IInbox);
}

interface ISequencerInboxGetter {
    function sequencerInbox() external view returns (ISequencerInbox);
}

interface IL1AddressRegistry is
    IRollupGetter,
    IInboxGetter,
    ISequencerInboxGetter,
    IBridgeGetter
{}
