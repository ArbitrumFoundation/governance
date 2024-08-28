// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SharedGovernorConstants} from "script/SharedGovernorConstants.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable-v5/governance/GovernorUpgradeable.sol";
import {CreateL2ArbSysProposal} from "script/helpers/CreateL2ArbSysProposal.sol";

contract SubmitUpgradeProposalScript is Script, SharedGovernorConstants, CreateL2ArbSysProposal {
    address PROPOSER_ADDRESS =
        vm.envOr("PROPOSER_ADDRESS", 0x1B686eE8E31c5959D9F5BBd8122a58682788eeaD); //L2Beat

    function run(address _timelockRolesUpgrader, uint256 _minDelay)
        public
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description,
            uint256 _proposalId
        )
    {
        return proposeUpgrade(_timelockRolesUpgrader, _minDelay);
    }

    function proposeUpgrade(address _timelockRolesUpgrader, uint256 _minDelay)
        internal
        returns (
            address[] memory _targets,
            uint256[] memory _values,
            bytes[] memory _calldatas,
            string memory _description,
            uint256 _proposalId
        )
    {
        // TODO: Before deployment update `_description` with the new governor contract addresses.
        _description =
            "# Proposal to Upgrade Governor Contracts \
  \
  ### **Abstract** \
  This proposal will transfer the proposer and canceller roles from the current Arbitrum Core Governor and Arbitrum Treasury Governor to newly deployed Governor contracts. This roles transfer is a crucial step in upgrading the Arbitrum DAO's governance infrastructure. \
  \
  ### Motivation \
  This upgrade to the Arbitrum DAO's governance system was initially discussed as part of the 'Expand Tally Support for the Arbitrum DAO' proposal https://forum.arbitrum.foundation/t/expand-tally-support-for-the-arbitrum-dao/22387. The community recognized the need for enhanced governance features, including proposal cancellation and flexible voting mechanisms. \
  \
  As a result of these discussions, new Governor contracts have been developed and deployed with these improvements. To activate these enhancements and complete the upgrade process, we now need to transfer the proposer role to these new contracts. \
  \
  ### **Specifications** \
  This proposal will: \
  \
  1. Grant the newly deployed Core Governor and Treasury Governor contracts the 'PROPOSER_ROLE' and 'CANCELLER_ROLE' on the timelock contract. \
  2. Revoke the current Core Governor and Treasury Governor contracts' 'PROPOSER_ROLE' and 'CANCELLER_ROLE' on the timelock contract. \
  \
  ### **Technical Details** \
  - The new Governor contracts have been deployed on Arbitrum One at the following addresses: \
    TODO: [Insert new Core Governor address] \
    TODO: [Insert new Treasury Governor address] \
  \
  - These new contracts include the following enhancements: \
    1. Proposal Cancellation: Allows the delegate who submitted a proposal to cancel it during the delay phase, before voting begins. \
    2. Flexible Voting: Enables delegates to cast rolling, fractional votes, supporting future innovations like voting from Orbit chains and more. \
  \
  - The new Governors maintain all existing features of the current Governors, including custom relay functionality and fractional quorum calculations. \
  \
  ### **Rationale** \
  The rationale for upgrading the Governors by granting and revoking roles on the Timelock contract instead of using the proxy upgradeable contract pattern is discussed in this forum post: https://forum.arbitrum.foundation/t/arbitrum-governance-smart-contract-upgrade-technical-details/24642 \
  \
  ### **Security Considerations** \
  - The new Governor contracts have been tested and audited by OpenZeppelin. \
  - This transfer does not move any funds or change permissions on the Timelock contracts. \
  - Historical governance actions will remain visible and valid. \
  \
  ### **Post-Transfer Actions** \
  - Immediately after this transfer executes, Tally will update to interface with the new Governor contracts. \
  - Delegates should use the new Governor contracts for all future proposal submissions. \
  - The old Governor contracts will remain on-chain but will no longer have the ability to execute proposals. \
  \
  ### **Timeline** \
  If this proposal passes, the transfer will be executed immediately after the Timelock delay. \
  \
  By approving this proposal, the Arbitrum DAO will upgrade its governance infrastructure, enabling new features and improvements in the governance process. \
  ";
        (_targets, _values, _calldatas) =
            createL2ArbSysProposal(_description, _timelockRolesUpgrader, _minDelay);
        vm.startBroadcast(PROPOSER_ADDRESS);
        _proposalId = GovernorUpgradeable(payable(L2_CORE_GOVERNOR)).propose(
            _targets, _values, _calldatas, _description
        );
        vm.stopBroadcast();
    }
}
