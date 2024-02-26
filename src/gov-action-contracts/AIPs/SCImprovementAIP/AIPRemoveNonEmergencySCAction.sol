// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../../security-council-mgmt/interfaces/ISecurityCouncilManager.sol";
import "../../../interfaces/ICoreTimelock.sol";

///@notice Effectively "remove" the non emergency security council; prevent it from proposing in the timelock and don't update it in security council elections
/// For discussion / rationale, see https://forum.arbitrum.foundation/t/rfc-constitutional-aip-security-council-improvement-proposal/20541
contract AIPRemoveNonEmergencySCAction {
    ISecurityCouncilManager public constant securityCouncilManager =
        ISecurityCouncilManager(0xD509E5f5aEe2A205F554f36E8a7d56094494eDFC);
    ICoreTimelock public constant timelock =
        ICoreTimelock(0x34d45e99f7D8c45ed05B5cA72D54bbD1fb3F98f0);
    address nonEmergecySC = 0xADd68bCb0f66878aB9D37a447C7b9067C5dfa941;

    function perform() external {
        // revoke SC's role on timelock
        timelock.revokeRole(timelock.PROPOSER_ROLE(), nonEmergecySC);

        // remove SC from elections
        securityCouncilManager.removeSecurityCouncil(
            SecurityCouncilData({
                securityCouncil: nonEmergecySC,
                updateAction: 0x9BF7b8884Fa381a45f8CB2525905fb36C996297a,
                chainId: 42_161
            })
        );
    }
}
