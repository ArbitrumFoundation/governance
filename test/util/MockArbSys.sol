// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

contract ArbSysMock {
    event ArbSysL2ToL1Tx(address from, address to, uint256 value, bytes indexed data);

    uint256 counter;

    function sendTxToL1(address destination, bytes calldata calldataForL1)
        external
        payable
        returns (uint256 exitNum)
    {
        exitNum = counter;
        counter = exitNum + 1;
        emit ArbSysL2ToL1Tx(msg.sender, destination, msg.value, calldataForL1);
        return exitNum;
    }
}
