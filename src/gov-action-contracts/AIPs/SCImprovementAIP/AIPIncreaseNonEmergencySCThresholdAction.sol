// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../governance/SetSCThresholdAndUpdateConstitutionAction.sol";
import "../../../interfaces/IArbitrumDAOConstitution.sol";

///@notice increase the non-emergency Security Council Threshold from 7 to 9 and update constitution accordingly.
/// For discussion / rationale, see https://forum.arbitrum.foundation/t/rfc-constitutional-aip-security-council-improvement-proposal/20541
/// Old constitution hash comes from election propoosal, see https://forum.arbitrum.foundation/t/aip-changes-to-the-constitution-and-the-security-council-election-process/20856/13
contract AIPIncreaseNonEmergencySCThresholdAction is SetSCThresholdAndUpdateConstitutionAction {
    constructor()
        SetSCThresholdAndUpdateConstitutionAction(
            IGnosisSafe(0xADd68bCb0f66878aB9D37a447C7b9067C5dfa941), // non emergency security council
            7, // old threshold
            9, // new threshold
            IArbitrumDAOConstitution(address(0x1D62fFeB72e4c360CcBbacf7c965153b00260417)), // DAO constitution
            bytes32(0xe794b7d0466ffd4a33321ea14c307b2de987c3229cf858727052a6f4b8a19cc1), //  constitution hash: election change, no threshold increase. https://github.com/ArbitrumFoundation/docs/tree/0837520dccc12e56a25f62de90ff9e3869196d05
            bytes32(0x7cc34e90dde73cfe0b4a041e79b5638e99f0d9547001e42b466c32a18ed6789d) // constitution hash: election change abd threshold increase.  https://github.com/ArbitrumFoundation/docs/pull/762/commits/88a6d38e15f1691c2ce7d31fe7c21e8fd52ac126
        ) 
    {}
}
