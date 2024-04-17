// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import "@arbitrum/nitro-contracts/src/osp/IOneStepProofEntry.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../../address-registries/L1AddressRegistry.sol";

interface IChallengeManagerUpgradeInit {
    // TODO
    function postUpgradeInit(IOneStepProofEntry osp_, bytes32 condRoot, IOneStepProofEntry condOsp)
        external;
    function osp() external returns (address);
}

// @notice set wasm module root and upgrade challenge manager for stylus ArbOS upgrade
contract AIPArbOS30UpgradeChallengeManagerAction {
    L1AddressRegistry public immutable l1AddressRegistry;
    bytes32 public immutable newWasmModuleRoot;
    ProxyAdmin public immutable govProxyAdmin;
    address public immutable newChallengeManagerImpl;
    IOneStepProofEntry public immutable osp;
    bytes32 immutable condRoot;
    IOneStepProofEntry public immutable condOsp;

    constructor(
        L1AddressRegistry _l1AddressRegistry,
        bytes32 _newWasmModuleRoot,
        ProxyAdmin _govProxyAdmin,
        address _newChallengeManagerImpl,
        IOneStepProofEntry _osp,
        bytes32 _condRoot,
        IOneStepProofEntry _condOsp
    ) {
        require(
            Address.isContract(address(_l1AddressRegistry)),
            "AIPArbOS30UpgradeChallengeManagerAction: l1AddressRegistry is not a contract"
        );
        require(
            Address.isContract(address(_govProxyAdmin)),
            "AIPArbOS30UpgradeChallengeManagerAction: _govProxyAdmin is not a contract"
        );
        require(
            Address.isContract(_newChallengeManagerImpl),
            "AIPArbOS30UpgradeChallengeManagerAction: _newChallengeManagerImpl is not a contract"
        );

        require(
            Address.isContract(address(_osp)),
            "AIPArbOS30UpgradeChallengeManagerAction: _osp is not a contract"
        );

        require(
            Address.isContract(address(_condOsp)),
            "AIPArbOS30UpgradeChallengeManagerAction: _condOsp is not a contract"
        );
        l1AddressRegistry = _l1AddressRegistry;
        newWasmModuleRoot = _newWasmModuleRoot;
        govProxyAdmin = _govProxyAdmin;
        newChallengeManagerImpl = _newChallengeManagerImpl;
        osp = _osp;
        condRoot = _condRoot;
        condOsp = _condOsp;
    }

    function peform() external {
        // set new wasm module root
        IRollupCore rollup = l1AddressRegistry.rollup();
        IRollupAdmin(address(rollup)).setWasmModuleRoot(newWasmModuleRoot);

        // verify:
        require(
            rollup.wasmModuleRoot() == newWasmModuleRoot,
            "AIPArbOS30UpgradeChallengeManagerAction: wasm module root not set"
        );

        // set the new challenge manager impl
        TransparentUpgradeableProxy challengeManager = TransparentUpgradeableProxy(
            payable(address(l1AddressRegistry.rollup().challengeManager()))
        );
        govProxyAdmin.upgradeAndCall(
            challengeManager,
            newChallengeManagerImpl,
            abi.encodeCall(IChallengeManagerUpgradeInit.postUpgradeInit, (osp, condRoot, condOsp))
        );

        // verify
        require(
            govProxyAdmin.getProxyImplementation(challengeManager) == newChallengeManagerImpl,
            "AIPArbOS30UpgradeChallengeManagerAction: new challenge manager implementation set"
        );
        require(
            IChallengeManagerUpgradeInit(address(challengeManager)).osp() == address(osp),
            "AIPArbOS30UpgradeChallengeManagerAction: new OSP not set"
        );
    }
}
