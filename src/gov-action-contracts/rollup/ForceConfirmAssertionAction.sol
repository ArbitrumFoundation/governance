// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/interfaces.sol";

contract ForceConfirmAssertionAction {
    IRollupGetter public immutable addressRegistry;

    constructor(IRollupGetter _addressRegistry) {
        addressRegistry = _addressRegistry;
    }

    function perform(bytes32 assertionHash, bytes32 parentAssertionHash, AssertionState calldata confirmState, bytes32 inboxAcc) external {
        IRollupAdmin(address(addressRegistry.rollup())).forceConfirmAssertion(
            assertionHash,
            parentAssertionHash,
            confirmState,
            inboxAcc
        );
    }
}
