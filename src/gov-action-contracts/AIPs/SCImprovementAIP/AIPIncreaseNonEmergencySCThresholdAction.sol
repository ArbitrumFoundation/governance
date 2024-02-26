// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../governance/SetSCThresholdAction.sol";

///@notice increase the non-emergency Security Council Threshold from 7 to 9.
/// For discussion / rationale, see https://forum.arbitrum.foundation/t/rfc-constitutional-aip-security-council-improvement-proposal/20541
contract AIPIncreaseNonEmergencySCThresholdAction is SetSCThresholdAction {
    constructor()
        SetSCThresholdAction(IGnosisSafe(0xADd68bCb0f66878aB9D37a447C7b9067C5dfa941), 7, 9)
    {}
}
