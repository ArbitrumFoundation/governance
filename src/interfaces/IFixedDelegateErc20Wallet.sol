// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IFixedDelegateErc20Wallet {
    function transfer(address _token, address _to, uint256 _amount) external returns (bool);
    function owner() external view returns (address);
}
