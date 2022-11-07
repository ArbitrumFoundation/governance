// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../src/TransferAndCallToken.sol";

contract MockTransferAndCallReceiver is ITransferAndCallReceiver {
    function onTokenTransfer(address, uint256, bytes memory) public override {}
}
