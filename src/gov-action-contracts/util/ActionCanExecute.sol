// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

contract ActionCanExecute {
    bool public canExecute;
    address public owner;

    constructor(bool _canExecuteInit, address _owner) {
        canExecute = _canExecuteInit;
        owner = _owner;
    }

    function setIsExecutable(bool _canExecute) external {
        require(msg.sender == owner, "NOT_OWNER");
        canExecute = _canExecute;
    }
}
