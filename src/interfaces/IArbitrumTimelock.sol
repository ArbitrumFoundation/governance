// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IArbitrumTimelock {
    function cancel(bytes32 id) external;
    function scheduleBatch(
        address[] calldata target,
        uint256[] calldata payloads,
        bytes[] calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;
    function getMinDelay() external view returns (uint256 duration);
    function updateDelay(uint256 newDelay) external;
}
