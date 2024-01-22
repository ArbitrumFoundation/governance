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
    function osp() external returns(address);
}

// CHRIS: TODO: rename with AIP number
 
/// @notice Upgrades the an arbitrum chain in preparation for 4844
/// @dev    Identical copies of this contract to be deployed for Arb One and Nova on Ethereum for the 4844 upgrade
contract AIP4844Action is SetWasmModuleRootAction {
    ProxyAdmin public immutable govProxyAdmin;
    L1AddressRegistry public immutable l1AddressRegistry;
    address public immutable newSequencerInboxImpl;
    address public immutable newChallengeManagerImpl;
    address public immutable newOsp;

    constructor(
                L1AddressRegistry _l1AddressRegistry, 
                bytes32 _newWasmModuleRoot,
                address _newSequencerInboxImpl,
                address _newChallengeMangerImpl,
                ProxyAdmin _govProxyAdmin) {
        require(
            Address.isContract(_11AddressRegistry),
            "AIP4844Action: _11AddressRegistry is not a contract"
        );
        l1AddressRegistry = _11AddressRegistry;

        require(
            _newWasmModuleRoot != bytes32(0),
            "AIP4844Action: _newWasmModuleRoot is empty"
        );
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
        newChallengeMangerImpl = _newChallengeMangerImpl;

        require(
            Address.isContract(_govProxyAdmin),
            "AIP4844Action: _govProxyAdmin is not a contract"
        );
        govProxyAdmin = _govProxyAdmin;
    }

    function perform() public {
        IRollupAdmin(rollup).setWasmModuleRoot(newWasmModuleRoot);

        // verify:
        require(
            IRollupCore(rollup).wasmModuleRoot() == newWasmModuleRoot,
            "AIP4844Action: wasm module root not set"
        );

        TransparentUpgradeableProxy sequencerInbox =
            TransparentUpgradeableProxy(payable(address(l1AddressRegistry.sequencerInbox())));
        (,uint64 futureBlocksBefore,,) = sequencerInbox.maxTimeVariation();
        govProxyAdmin.upgradeAndCall(sequencerInbox, newSequencerInboxImpl, abi.encodePacked(IPostUpgradeInit.postUpgradeInit.selector));

        // verify
        require(
            govProxyAdmin.getProxyImplementation(sequencerInbox) == newSequencerInboxImpl,
            "AIP4844Action: new seq inbox implementation set"
        );
        (,uint64 futureBlocksAfter,,) = sequencerInbox.maxTimeVariation();
        require(
            futureBlocksBefore != 0 && futureBlocksBefore == futureBlocksAfter, 
            "AIP4844Action: maxTimeVariation not set"
        )

        // set the new challenge manager impl
        TransparentUpgradeableProxy challengeManager =
            TransparentUpgradeableProxy(payable(address(l1AddressRegistry.rollup().challengeManager())));
        govProxyAdmin.upgradeAndCall(challengeManager, newChallengeManagerImpl, abi.encodePacked(IChallengeManagerUpgradeInit.postUpgradeInit.selector, newOsp));

        require(
            IChallengeManagerUpgradeInit(challengeManager).osp() == newOsp, 
            "AIP4844Action: new OSP not set"
        );
    }
}
