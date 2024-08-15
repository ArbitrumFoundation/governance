// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../address-registries/L1AddressRegistry.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface ISeqInbox {
    function batchPosterManager() external view returns (address);
    function setBatchPosterManager(address newBatchPosterManager) external;
}

/// @notice Sets the batch poster manager role
/// @dev    This contract is dependent on AIP4844Action having run already, since that action upgrades
///         the sequencer inbox to the have the batch poster manager role
contract SetBatchPosterManager {
    L1AddressRegistry public immutable l1AddressRegistry;
    address public immutable batchPosterManager;

    constructor(L1AddressRegistry _l1AddressRegistry, address _batchPosterManager) {
        require(
            Address.isContract(address(_l1AddressRegistry)),
            "SetBatchPosterManager: _l1AddressRegistry is not a contract"
        );
        l1AddressRegistry = _l1AddressRegistry;
        batchPosterManager = _batchPosterManager;
    }

    function perform() public {
        ISeqInbox seqInbox = ISeqInbox(address(l1AddressRegistry.sequencerInbox()));
        seqInbox.setBatchPosterManager(batchPosterManager);

        require(
            seqInbox.batchPosterManager() == batchPosterManager,
            "SetBatchPosterManager: Failed to set batch poster manager"
        );
    }
}
