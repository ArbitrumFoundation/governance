// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./MockArbSys.sol";

import "forge-std/Test.sol";


import "@arbitrum/nitro-contracts/src/bridge/Inbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/SequencerInbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/Bridge.sol";
import "@arbitrum/nitro-contracts/src/bridge/Outbox.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

abstract contract XChainTest is Test, IOwnable {
    ArbSys public arbsys;
    IInbox public delayedInbox;
    IBridge public bridge;
    ISequencerInbox public sequencerInbox;
    Outbox public outbox;
    IRollupUser public rolllup;

    address sequencer = address(bytes20(keccak256(abi.encode("sequencer addr"))));

    constructor() {
        arbsys = ArbSys(address(100));
        vm.etch(address(arbsys), address(new MockArbSys()).code);

        delayedInbox = IInbox(address(new TransparentUpgradeableProxy(address(new Inbox()), address(this), bytes(""))));
        sequencerInbox = ISequencerInbox(
            address(new TransparentUpgradeableProxy(address(new SequencerInbox()), address(this), bytes("")))
        );
        bridge = IBridge(address(new TransparentUpgradeableProxy(address(new Bridge()), address(this), bytes(""))));
        outbox = Outbox(address(new TransparentUpgradeableProxy(address(new Outbox()), address(this), bytes(""))));

        Inbox(address(delayedInbox)).initialize(bridge, sequencerInbox);
        SequencerInbox(address(sequencerInbox)).initialize(
            bridge,
            ISequencerInbox.MaxTimeVariation({
                delayBlocks: 100,
                futureBlocks: 100,
                delaySeconds: 100,
                futureSeconds: 100
            })
        );
        Bridge(address(bridge)).initialize(this);
        outbox.initialize(bridge);

        bridge.setSequencerInbox(address(sequencerInbox));
        bridge.setDelayedInbox(address(delayedInbox), true);
        bridge.setOutbox(address(outbox), true);
    }

    function owner() external view returns (address) {
        return address(this);
    }
}
