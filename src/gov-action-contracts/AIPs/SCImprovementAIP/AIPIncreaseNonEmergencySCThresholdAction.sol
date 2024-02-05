// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../governance/SetSCThresholdAndConditionallyUpdateConstitutionAction.sol";
import "../../../interfaces/IArbitrumDAOConstitution.sol";


///@notice increase the non-emergency Security Council Threshold from 7 to 9 and update constitution accordingly. 
/// For discussion / rationale, see https://forum.arbitrum.foundation/t/rfc-constitutional-aip-security-council-improvement-proposal/20541
/// Constitution hash updates depends on whether election change AIP passes; see https://forum.arbitrum.foundation/t/aip-changes-to-the-constitution-and-the-security-council-election-process/20856/13
contract AIPIncreaseNonEmergencySCThresholdAction is SetSCThresholdAndConditionallyUpdateConstitutionAction {
    constructor()
        SetSCThresholdAndConditionallyUpdateConstitutionAction(
            IGnosisSafe(0xADd68bCb0f66878aB9D37a447C7b9067C5dfa941),  // non emergency security council
            7,  // old threshold
            9,  // new threshold
            IArbitrumDAOConstitution(address(0x1D62fFeB72e4c360CcBbacf7c965153b00260417)), // DAO constitution 
             bytes32(0x60acde40ad14f4ecdb1bea0704d1e3889264fb029231c9016352c670703b35d6), // 1. constitution hash: no election change, no threshold increase. https://github.com/ArbitrumFoundation/docs/tree/8071e3468cc0122e33c88ab7510c7c4320d35929
             bytes32(""), // 2. constitution hash: no election change, yes threshold increase.  TODO link
             bytes32(0xe794b7d0466ffd4a33321ea14c307b2de987c3229cf858727052a6f4b8a19cc1), // 3. constitution hash: yes election change, no threshold increase. https://github.com/ArbitrumFoundation/docs/tree/0837520dccc12e56a25f62de90ff9e3869196d05
              bytes32(""))// 4. constitution hash: yes election change, yes threshold.  TODO link
              // if 1, that means election change AIP didn't pass; apply threshold increase changes (2) on top of 1.
              // if 3, that means election change AIP did pass; apply threshold increase changes (4) on top of 3.
    {}
}
