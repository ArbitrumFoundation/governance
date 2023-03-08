// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "@arbitrum/nitro-contracts/src/bridge/Bridge.sol";
import "@arbitrum/nitro-contracts/src/bridge/SequencerInbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/Inbox.sol";

import "@arbitrum/nitro-contracts/src/bridge/ISequencerInbox.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "../util/TestUtil.sol";
import "../../src/UpgradeExecutor.sol";
import "../../src/gov-action-contracts/address-registries/L1AddressRegistry.sol" as _ar;
import "../../src/gov-action-contracts/address-registries/interfaces.sol" as _ifaces;

contract OwnableStub is Ownable {}

contract OutboxStub {}

abstract contract ActionTestBase {
    address executor0 = address(138);
    address executor1 = address(139);

    address[] outboxesToAdd;
    address[] outboxesToRemove;

    UpgradeExecutor ue;
    Ownable rollup;
    Bridge bridge;
    SequencerInbox si;
    Inbox inbox;
    _ar.L1AddressRegistry addressRegistry;
    _ifaces.IBridgeGetter bridgeGetter;
    _ifaces.IInboxGetter inboxGetter;
    _ifaces.ISequencerInboxGetter sequencerInboxGetter;

    function setUp() public {
        outboxesToAdd =
            [address(new OutboxStub()), address(new OutboxStub()), address(new OutboxStub())];
        outboxesToRemove.push(outboxesToAdd[0]);
        outboxesToRemove.push(outboxesToAdd[1]);

        ue = UpgradeExecutor(TestUtil.deployProxy(address(new UpgradeExecutor())));
        address[] memory executors = new address[](2);

        executors[0] = executor0;
        executors[1] = executor1;
        ue.initialize(address(ue), executors);

        rollup = new OwnableStub();
        rollup.transferOwnership(address(ue));
        bridge = Bridge(TestUtil.deployProxy(address(new Bridge())));
        bridge.initialize(IOwnable(address(rollup)));
        si = SequencerInbox(TestUtil.deployProxy(address(new SequencerInbox())));
        si.initialize(bridge, ISequencerInbox.MaxTimeVariation(0, 0, 0, 0));
        inbox = Inbox(TestUtil.deployProxy(address(new Inbox())));
        inbox.initialize(bridge, si);
        addressRegistry = new _ar.L1AddressRegistry(IInbox(address(inbox)));
        bridgeGetter = _ifaces.IBridgeGetter(address(addressRegistry));
        inboxGetter = _ifaces.IInboxGetter(address(addressRegistry));
        sequencerInboxGetter = _ifaces.ISequencerInboxGetter(address(addressRegistry));
    }
}
