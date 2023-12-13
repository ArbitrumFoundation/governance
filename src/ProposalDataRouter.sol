// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./UpgradeExecRouteBuilder.sol";

/// @notice Uses the UpgradeExecRouteBuilder to build a proposals calldata and send it to the L1Timelock.
/// Alternative to creating a proposal directly from the L1Timelock; has simpler, human readable inputs.
contract ProposalDataRouter is Initializable, OwnableUpgradeable {
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

    /// @param _upgradeExecRouteBuilder UpgradeExecRouteBuilder contract address
    /// @param _l2CoreTimelockAddr Core governance governance-chain timelock address
    function initialize(
        address _upgradeExecRouteBuilder,
        address _l2CoreTimelockAddr,
        address _owner
    ) external initializer {
        _setUpgradeExecRouteBuilder(_upgradeExecRouteBuilder);
        l2CoreTimelockAddr = _l2CoreTimelockAddr;
        transferOwnership(_owner);
    }

    /// @param _upgradeExecRouteBuilder new router address
    function _setUpgradeExecRouteBuilder(address _upgradeExecRouteBuilder) internal {
        if (!Address.isContract(_upgradeExecRouteBuilder)) {
            revert NotAContract(_upgradeExecRouteBuilder);
        }

        upgradeExecRouteBuilder = UpgradeExecRouteBuilder(_upgradeExecRouteBuilder);
        emit UpgradeExecRouteBuilderSet(_upgradeExecRouteBuilder);
    }

    /// @notice UpgradeExecRouteBuilder is immutable, so in lieu of upgrading it, it can be redeployed and reset here
    /// @param _upgradeExecRouteBuilder new router address
    function setUpgradeExecRouteBuilder(address _upgradeExecRouteBuilder) external onlyOwner {
        _setUpgradeExecRouteBuilder(_upgradeExecRouteBuilder);
    }
    /// @notice generate salt for parent chain timelock.
    /// @param _actionAddresses Action address array (input to salt)
    /// @param _nonce input to salt

    function generateSalt(address[] memory _actionAddresses, uint256 _nonce)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_actionAddresses, _nonce));
    }

    ///@notice Uses UpgradeExecRouteBuilder to build proposal data and then sends it to parent chain.
    /// Only core gov timelock and can call.
    /// @param _chainIds         Chain ids containing the actions to be called
    /// @param _actionAddresses  Addresses of the action contracts to be called
    /// @param _actionValues     Values to call the action contracts with
    /// @param _actionDatas      Call data to call the action contracts with
    /// @param _predecessor      A predecessor value for the l1 timelock operation
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

    /// @notice Uses UpgradeExecRouteBuilder to build proposal data and then sends it to parent chain.
    /// Only core gov timelock and can call.
    /// For values, calldatas, and predecessor, uses defaults set in UpgradeExecRouteBuilder.
    /// @param _chainIds         Chain ids containing the actions to be called
    /// @param _actionAddresses  Addresses of the action contracts to be called
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

    /// @notice Send calldata to parent chain. Updates parents chain timelock nonce.
    /// @param _payload calldata to send to parent chain
    function _sendProposalDataToL1(bytes memory _payload) internal {
        (bool success,) = address(100).call{value: msg.value}(_payload);
        if (!success) {
            revert ArbSysCallFailed(_payload);
        }
        nonce = nonce + 1;
    }
}
