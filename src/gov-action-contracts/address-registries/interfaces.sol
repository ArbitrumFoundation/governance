// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/bridge/IBridge.sol";
import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import "@arbitrum/nitro-contracts/src/bridge/ISequencerInbox.sol";

interface IRollupCore {
    function pause() external;
    function resume() external;
    function forceResolveChallenge(address[] memory stackerA, address[] memory stackerB) external;
    function outbox() external view returns (IOutbox);
    function setOutbox(IOutbox _outbox) external;
    function setValidator(address[] memory _validator, bool[] memory _val) external;
    function setValidatorWhitelistDisabled(bool _validatorWhitelistDisabled) external;
}

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

interface IL1AddressRegistry is
    IRollupGetter,
    IInboxGetter,
    ISequencerInboxGetter,
    IBridgeGetter,
    IL1TimelockGetter
{}
