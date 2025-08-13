// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "@arbitrum/nitro-contracts/src/bridge/Bridge.sol";
import "@arbitrum/nitro-contracts/src/bridge/SequencerInbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/Inbox.sol";

import "@arbitrum/nitro-contracts/src/bridge/ISequencerInbox.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../src/L2ArbitrumGovernor.sol";
import "../../src/L2ArbitrumToken.sol";
import "../../src/ArbitrumTimelock.sol";
import "../../src/L1ArbitrumTimelock.sol";
import "../../src/FixedDelegateErc20Wallet.sol";
import "../util/TestUtil.sol";
import "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
import "../../src/ArbitrumDAOConstitution.sol";
import "../../src/gov-action-contracts/address-registries/L1AddressRegistry.sol" as _ar;
import "../../src/gov-action-contracts/address-registries/L2AddressRegistry.sol" as _ar1;
import "../../src/gov-action-contracts/address-registries/interfaces.sol" as _ifaces;

contract OwnableStub is Ownable {}

contract OutboxStub {}

abstract contract ActionTestBase {
    address executor0 = address(138);
    address executor1 = address(139);
    address executor2 = address(140);

    bytes32 constitutionHash = bytes32("0x010101");

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
    L1ArbitrumTimelock l1Timelock;

    UpgradeExecutor arbOneUe;
    L2ArbitrumGovernor coreGov;
    L2ArbitrumToken arbOneToken;
    ArbitrumTimelock coreTimelock;
    L2ArbitrumGovernor treasuryGov;
    ArbitrumTimelock treasuryTimelock;
    ArbitrumDAOConstitution arbitrumDAOConstitution;
    _ar1.L2AddressRegistry arbOneAddressRegistry;
    FixedDelegateErc20Wallet treasuryWallet;

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
        // nitro-testnode's L1 is not an Arbitrum chain, so IReader4844 must be a non-zero address
        si = SequencerInbox(TestUtil.deployProxy(address(new SequencerInbox(117964, IReader4844(address(1)), false, false))));
        si.initialize(bridge, ISequencerInbox.MaxTimeVariation(0, 0, 0, 0), BufferConfig(0, 0, 0), IFeeTokenPricer(address(0)));
        inbox = Inbox(TestUtil.deployProxy(address(new Inbox(117964))));
        inbox.initialize(bridge, si);

        l1Timelock =
            L1ArbitrumTimelock(payable(TestUtil.deployProxy(address(new L1ArbitrumTimelock()))));
        address[] memory l1Proposers = new address[](1);
        l1Proposers[0] = address(bridge);
        l1Timelock.initialize(5, l1Proposers, new address[](0));
        l1Timelock.grantRole(l1Timelock.TIMELOCK_ADMIN_ROLE(), address(ue));
        l1Timelock.revokeRole(l1Timelock.TIMELOCK_ADMIN_ROLE(), address(l1Timelock));
        l1Timelock.revokeRole(l1Timelock.TIMELOCK_ADMIN_ROLE(), address(this));

        addressRegistry =
        new _ar.L1AddressRegistry(IInbox(address(inbox)), _ifaces.IL1Timelock(address(l1Timelock)), _ifaces.IL1CustomGateway(address(0)), _ifaces.IL1GatewayRouter(address(0)));
        bridgeGetter = _ifaces.IBridgeGetter(address(addressRegistry));
        inboxGetter = _ifaces.IInboxGetter(address(addressRegistry));
        sequencerInboxGetter = _ifaces.ISequencerInboxGetter(address(addressRegistry));

        arbOneUe = UpgradeExecutor(TestUtil.deployProxy(address(new UpgradeExecutor())));
        address[] memory executors2 = new address[](1);
        executors2[0] = executor2;
        arbOneUe.initialize(address(arbOneUe), executors2);

        arbitrumDAOConstitution = new ArbitrumDAOConstitution(constitutionHash);
        arbitrumDAOConstitution.transferOwnership(address(arbOneUe));

        arbOneToken = L2ArbitrumToken(TestUtil.deployProxy(address(new L2ArbitrumToken())));
        arbOneToken.initialize(address(4567), 10_000_000_000, address(arbOneUe));
        coreTimelock =
            ArbitrumTimelock(payable(TestUtil.deployProxy(address(new ArbitrumTimelock()))));
        coreGov =
            L2ArbitrumGovernor(payable(TestUtil.deployProxy(address(new L2ArbitrumGovernor()))));
        address[] memory proposers = new address[](1);
        proposers[0] = address(coreGov);
        coreTimelock.initialize(5, proposers, new address[](0));
        coreTimelock.grantRole(coreTimelock.TIMELOCK_ADMIN_ROLE(), address(arbOneUe));
        coreTimelock.revokeRole(coreTimelock.TIMELOCK_ADMIN_ROLE(), address(coreTimelock));
        coreTimelock.revokeRole(coreTimelock.TIMELOCK_ADMIN_ROLE(), address(this));
        coreGov.initialize(arbOneToken, coreTimelock, address(arbOneUe), 3, 4, 500, 50, 50);

        treasuryTimelock =
            ArbitrumTimelock(payable(TestUtil.deployProxy(address(new ArbitrumTimelock()))));
        treasuryGov =
            L2ArbitrumGovernor(payable(TestUtil.deployProxy(address(new L2ArbitrumGovernor()))));
        address[] memory proposers2 = new address[](1);
        proposers[0] = address(treasuryGov);
        treasuryTimelock.initialize(7, proposers2, new address[](0));
        treasuryTimelock.grantRole(treasuryTimelock.TIMELOCK_ADMIN_ROLE(), address(arbOneUe));
        treasuryTimelock.revokeRole(
            treasuryTimelock.TIMELOCK_ADMIN_ROLE(), address(treasuryTimelock)
        );
        treasuryTimelock.revokeRole(treasuryTimelock.TIMELOCK_ADMIN_ROLE(), address(this));
        treasuryGov.initialize(arbOneToken, treasuryTimelock, address(arbOneUe), 7, 8, 600, 60, 60);

        treasuryWallet =
            FixedDelegateErc20Wallet(TestUtil.deployProxy(address(new FixedDelegateErc20Wallet())));
        treasuryWallet.initialize(
            address(arbOneToken), treasuryGov.EXCLUDE_ADDRESS(), address(treasuryTimelock)
        );

        arbOneAddressRegistry =
        new _ar1.L2AddressRegistry(_ar1.IL2ArbitrumGoverner(address(coreGov)), _ar1.IL2ArbitrumGoverner(address(treasuryGov)), _ar1.IFixedDelegateErc20Wallet(address(treasuryWallet)), _ar1.IArbitrumDAOConstitution(address(arbitrumDAOConstitution)));
    }
}
