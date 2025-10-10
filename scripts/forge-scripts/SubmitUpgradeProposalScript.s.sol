// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import {Script} from "forge-std/Script.sol";
import {DeployConstants} from "scripts/forge-scripts/DeployConstants.sol";
import "node_modules/@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {EncodeL2ArbSysProposal} from "scripts/forge-scripts/utils/EncodeL2ArbSysProposal.sol";

contract SubmitUpgradeProposalScript is Script, DeployConstants, EncodeL2ArbSysProposal {
    address PROPOSER_ADDRESS =
        vm.envOr("PROPOSER_ADDRESS", 0x1B686eE8E31c5959D9F5BBd8122a58682788eeaD); //TODO: Update proposer address.
    string PROPOSAL_DESCRIPTION =
        vm.envOr("PROPOSAL_DESCRIPTION", string("Add proposal description here")); // TODO: Update proposal description.

    function run(address _multiProxyUpgradeAction, uint256 _minDelay)
        public
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description,
            uint256 _proposalId
        )
    {
        return proposeUpgrade(_multiProxyUpgradeAction, _minDelay);
    }

    function proposeUpgrade(address _multiProxyUpgradeAction, uint256 _minDelay)
        internal
        returns (
            address[] memory _targets,
            uint256[] memory _values,
            bytes[] memory _calldatas,
            string memory _description,
            uint256 _proposalId
        )
    {
        _description = PROPOSAL_DESCRIPTION;
        (_targets, _values, _calldatas) =
            encodeL2ArbSysProposal(_description, _multiProxyUpgradeAction, _minDelay);
        vm.startBroadcast(PROPOSER_ADDRESS);
        _proposalId = GovernorUpgradeable(payable(L2_CORE_GOVERNOR))
            .propose(_targets, _values, _calldatas, _description);
        vm.stopBroadcast();
    }
}
