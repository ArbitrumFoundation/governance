// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./MockArbSys.sol";

import "forge-std/Test.sol";

import "@arbitrum/nitro-contracts/bridge/Inbox.sol";
import "@arbitrum/nitro-contracts/bridge/SequencerInbox.sol";
import "@arbitrum/nitro-contracts/bridge/Bridge.sol";

abstract contract XChainTest is Test {
    ArbSys arbsys;
    IInbox delayedInbox;
    IBridge bridge;
    ISequencerInbox sequencerInbox;
    address sequencer = address(bytes20(keccak256(abi.encode("sequencer addr"))));

    constructor() {
        arbsys = new MockArbSys();
        delayedInbox = new Inbox();
        sequencerInbox = new SequencerInbox();
    }
}
