// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./UpgradeExecRouteBuilder.sol";

/// @notice Uses the UpgradeExecRouteBuilder to build a proposals calldata and send it to the L1Timelock. 
/// Alternative to creating a proposal directly from the L1Timelock; has simpler, human readable inputs.
contract ProposalDataRouter is OwnableUpgradeable {
    UpgradeExecRouteBuilder public upgradeExecRouteBuilder;
    address public l2CoreTimelockAddr;
    // nonce to ensure uniqueness of l1 timelock salts
    uint256 private nonce;

    event UpgradeExecRouteBuilderSet(address addr);
    event ProposalDataSent(uint256[] chainIds, address[] actionsAddressses);

    error ArbSysCallFailed(bytes payload);

    constructor() {
        _disableInitializers();
    }

    modifier onlyFromCoreTimelock() {
        require(msg.sender == l2CoreTimelockAddr);
        _;
    }

    function initialize(address _upgradeExecRouteBuilder, address _l2CoreTimelockAddr)
        external
        initializer
    {
        _setUpgradeExecRouteBuilder(_upgradeExecRouteBuilder);
        l2CoreTimelockAddr = _l2CoreTimelockAddr;
    }

    function _setUpgradeExecRouteBuilder(address _upgradeExecRouteBuilder) internal {
        if (!Address.isContract(_upgradeExecRouteBuilder)) {
            revert NotAContract(_upgradeExecRouteBuilder);
        }

        upgradeExecRouteBuilder = UpgradeExecRouteBuilder(_upgradeExecRouteBuilder);
        emit UpgradeExecRouteBuilderSet(_upgradeExecRouteBuilder);
    }

    /// @notice UpgradeExecRouteBuilder is immutable, so in lieu of upgrading it, it can be redeployed and reset here
    /// @param _upgradeExecRouteBuilder new router address    
        _setUpgradeExecRouteBuilder(_upgradeExecRouteBuilder);
    }

    function generateSalt(address[] memory _actionAddresses, uint256 _nonce)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_actionAddresses, _nonce));
    }

    function buildAndSendProposalData(
        uint256[] memory _chainIds,
        address[] memory _actionAddresses,
        uint256[] memory _actionValues,
        bytes[] memory _actionDatas,
        bytes32 _predecessor
    ) external onlyFromCoreTimelock {
        (, bytes memory payload) = upgradeExecRouteBuilder.createActionRouteData(
            _chainIds,
            _actionAddresses,
            _actionValues,
            _actionDatas,
            _predecessor,
            this.generateSalt(_actionAddresses, nonce)
        );
        _sendProposalDataToL1(payload);

        emit ProposalDataSent(_chainIds, _actionAddresses);
    }

    function buildAndSendProposalDataWithDefaults(
        uint256[] memory _chainIds,
        address[] memory _actionAddresses
    ) external onlyFromCoreTimelock {
        (, bytes memory payload) = upgradeExecRouteBuilder.createActionRouteDataWithDefaults(
            _chainIds, _actionAddresses, this.generateSalt(_actionAddresses, nonce)
        );
        _sendProposalDataToL1(payload);
        emit ProposalDataSent(_chainIds, _actionAddresses);
    }

    function _sendProposalDataToL1(bytes memory payload) internal {
        (bool success,) = address(100).call{value: msg.value}(payload);
        if (!success) {
            revert ArbSysCallFailed(payload);
        }
        nonce = nonce + 1;
    }
}
