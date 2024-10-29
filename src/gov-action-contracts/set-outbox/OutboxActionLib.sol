// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";

library OutboxActionLib {
    function bridgeAddOutboxes(IBridgeGetter addressRegistry, address[] calldata outboxes)
        internal
    {
        IBridge bridge = addressRegistry.bridge();
        for (uint256 i = 0; i < outboxes.length; i++) {
            address outbox = outboxes[i];
            require(Address.isContract(outbox), "BridgeAddOutboxesAction: outbox must be contract");
            require(
                !bridge.allowedOutboxes(outbox), "BridgeAddOutboxesAction: outbox already allowed"
            );
            bridge.setOutbox(outbox, true);
        }
    }

    function bridgeRemoveOutboxes(IBridgeGetter addressRegistry, address[] calldata outboxes)
        internal
    {
        IBridge bridge = addressRegistry.bridge();
        for (uint256 i = 0; i < outboxes.length; i++) {
            address outbox = outboxes[i];
            require(
                bridge.allowedOutboxes(outbox),
                "BridgeRemoveOutboxesAction: provided outbox already not allowed"
            );
            bridge.setOutbox(outbox, false);
        }
    }

    function bridgeRemoveAllOutboxes(IBridgeGetter addressRegistry) internal {
        IBridge bridge = addressRegistry.bridge();
        while (true) {
            try bridge.allowedOutboxList(0) returns (address outbox) {
                bridge.setOutbox(outbox, false);
            } catch {
                break;
            }
        }
    }

    function rollupSetOutboxAction(IRollupGetter addressRegistry, IOutbox outbox) internal {
        require(
            Address.isContract(address(outbox)), "SetRollupOutboxAction: outbox must be contract"
        );
        IRollupAdmin(address(addressRegistry.rollup())).setOutbox(outbox);
    }
}
