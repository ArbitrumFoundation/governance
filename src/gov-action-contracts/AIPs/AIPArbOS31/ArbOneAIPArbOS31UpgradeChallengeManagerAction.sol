// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./parent_contracts/AIPArbOS31UpgradeChallengeManagerAction.sol";
import "@arbitrum/nitro-contracts/src/osp/IOneStepProofEntry.sol";
import "../../address-registries/L1AddressRegistry.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @notice for deloployment on L1 Ethereum
contract ArbOneAIPArbOS31UpgradeChallengeManagerAction is
    AIPArbOS31UpgradeChallengeManagerAction
{
    constructor()
        AIPArbOS31UpgradeChallengeManagerAction(
            L1AddressRegistry(0xd514C2b3aaBDBfa10800B9C96dc1eB25427520A0), // l1 address registry
            bytes32(0), // wasm module root TODO
            ProxyAdmin(0x554723262467F125Ac9e1cDFa9Ce15cc53822dbD), // l1 core proxy admin
            address(0), // challenge manager impl TODO
            IOneStepProofEntry(address(0)), // new osp TODO)
            0x8b104a2e80ac6165dc58b9048de12f301d70b02a0ab51396c22b4b4b802a16a4, // cond root
            IOneStepProofEntry(address(0)) // cond osp TODO
        )
    {}
}
