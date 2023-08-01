// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/bridge/IBridge.sol";
import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/ISequencerInbox.sol";
import "@arbitrum/nitro-contracts/src/rollup/IRollupAdmin.sol";
import "@arbitrum/nitro-contracts/src/rollup/IRollupLogic.sol";

interface IL1Timelock {
    function updateDelay(uint256 newDelay) external;
    function getMinDelay() external view returns (uint256 duration);
}

interface IRollupGetter {
    function rollup() external view returns (IRollupCore);
}

interface IBridgeGetter {
    function bridge() external view returns (IBridge);
}

interface IInboxGetter {
    function inbox() external view returns (IInbox);
}

interface ISequencerInboxGetter {
    function sequencerInbox() external view returns (ISequencerInbox);
}

interface IL1TimelockGetter {
    function l1Timelock() external view returns (IL1Timelock);
}

interface IL1GatewayRouter {
    function setGateways(
        address[] memory _token,
        address[] memory _gateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable returns (uint256);
}

interface IL1CustomGateway {
    function forceRegisterTokenToL2(
        address[] calldata _l1Addresses,
        address[] calldata _l2Addresses,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost
    ) external payable returns (uint256);
}

interface IL1CustomGatewayGetter {
    function customGateway() external view returns (IL1CustomGateway);
}

interface IL1GatewayRouterGetter {
    function gatewayRouter() external view returns (IL1GatewayRouter);
}

interface IL1AddressRegistry is
    IRollupGetter,
    IInboxGetter,
    ISequencerInboxGetter,
    IBridgeGetter,
    IL1TimelockGetter,
    IL1GatewayRouterGetter,
    IL1CustomGatewayGetter
{}
