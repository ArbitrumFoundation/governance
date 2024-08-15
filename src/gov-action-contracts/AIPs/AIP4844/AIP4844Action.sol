// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../address-registries/L1AddressRegistry.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface ISeqInboxPostUpgradeInit {
    function postUpgradeInit() external;
}

interface IChallengeManagerUpgradeInit {
    function postUpgradeInit(address _newOsp) external;
    function osp() external returns (address);
}

/// @notice Upgrades an arbitrum chain in preparation for 4844
/// @dev    Identical copies of this contract to be deployed for Arb One and Nova on Ethereum for the 4844 upgrade
contract AIP4844Action {
    ProxyAdmin public immutable govProxyAdmin;
    L1AddressRegistry public immutable l1AddressRegistry;
    address public immutable newSequencerInboxImpl;
    address public immutable newChallengeManagerImpl;
    address public immutable newOsp;
    bytes32 public immutable newWasmModuleRoot;

    constructor(
        L1AddressRegistry _l1AddressRegistry,
        bytes32 _newWasmModuleRoot,
        address _newSequencerInboxImpl,
        address _newChallengeMangerImpl,
        ProxyAdmin _govProxyAdmin,
        address _newOsp
    ) {
        require(
            Address.isContract(address(_l1AddressRegistry)),
            "AIP4844Action: _l1AddressRegistry is not a contract"
        );
        l1AddressRegistry = _l1AddressRegistry;

        require(_newWasmModuleRoot != bytes32(0), "AIP4844Action: _newWasmModuleRoot is empty");
        newWasmModuleRoot = _newWasmModuleRoot;

        require(
            Address.isContract(_newSequencerInboxImpl),
            "AIP4844Action: _newSequencerInboxImpl is not a contract"
        );
        newSequencerInboxImpl = _newSequencerInboxImpl;

        require(
            Address.isContract(_newChallengeMangerImpl),
            "AIP4844Action: _newChallengeMangerImpl is not a contract"
        );
        newChallengeManagerImpl = _newChallengeMangerImpl;

        require(
            Address.isContract(address(_govProxyAdmin)),
            "AIP4844Action: _govProxyAdmin is not a contract"
        );
        govProxyAdmin = _govProxyAdmin;

        require(Address.isContract(address(_newOsp)), "AIP4844Action: _newOsp is not a contract");
        newOsp = _newOsp;
    }

    function perform() public {
        IRollupCore rollup = l1AddressRegistry.rollup();
        IRollupAdmin(address(rollup)).setWasmModuleRoot(newWasmModuleRoot);

        // verify:
        require(
            rollup.wasmModuleRoot() == newWasmModuleRoot, "AIP4844Action: wasm module root not set"
        );

        TransparentUpgradeableProxy sequencerInbox =
            TransparentUpgradeableProxy(payable(address(l1AddressRegistry.sequencerInbox())));
        (, uint256 futureBlocksBefore,,) =
            ISequencerInbox(address(sequencerInbox)).maxTimeVariation();
        govProxyAdmin.upgradeAndCall(
            sequencerInbox,
            newSequencerInboxImpl,
            abi.encodeCall(ISeqInboxPostUpgradeInit.postUpgradeInit, ())
        );

        // verify
        require(
            govProxyAdmin.getProxyImplementation(sequencerInbox) == newSequencerInboxImpl,
            "AIP4844Action: new seq inbox implementation set"
        );
        (, uint256 futureBlocksAfter,,) =
            ISequencerInbox(address(sequencerInbox)).maxTimeVariation();
        require(
            futureBlocksBefore != 0 && futureBlocksBefore == futureBlocksAfter,
            "AIP4844Action: maxTimeVariation not set"
        );

        // set the new challenge manager impl
        TransparentUpgradeableProxy challengeManager = TransparentUpgradeableProxy(
            payable(address(l1AddressRegistry.rollup().challengeManager()))
        );
        govProxyAdmin.upgradeAndCall(
            challengeManager,
            newChallengeManagerImpl,
            abi.encodeCall(IChallengeManagerUpgradeInit.postUpgradeInit, (newOsp))
        );

        require(
            govProxyAdmin.getProxyImplementation(challengeManager) == newChallengeManagerImpl,
            "AIP4844Action: new challenge manager implementation set"
        );
        require(
            IChallengeManagerUpgradeInit(address(challengeManager)).osp() == newOsp,
            "AIP4844Action: new OSP not set"
        );
    }
}
