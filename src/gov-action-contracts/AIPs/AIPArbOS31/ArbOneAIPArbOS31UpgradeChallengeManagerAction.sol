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
            0x260f5fa5c3176a856893642e149cf128b5a8de9f828afec8d11184415dd8dc69, // wasm module root
            ProxyAdmin(0x554723262467F125Ac9e1cDFa9Ce15cc53822dbD), // l1 core proxy admin
            0x914B7b3053B35B84A24df08D7c9ceBCaEA4E2948, // challenge manager impl
            IOneStepProofEntry(0xa328BAF257A937b7934429a5d8458d98693C6FC7), // new osp
            0x8b104a2e80ac6165dc58b9048de12f301d70b02a0ab51396c22b4b4b802a16a4, // cond root
            IOneStepProofEntry(0x83fA8eD860514370fbcC5f04eA7969475F48CfEb) // cond osp
        )
    {}
}
