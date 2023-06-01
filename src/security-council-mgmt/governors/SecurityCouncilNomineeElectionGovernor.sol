// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorPreventLateQuorumUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

import "../interfaces/ISecurityCouncilManager.sol";
import "./SecurityCouncilNomineeElectionGovernorCounting.sol";
import "./ArbitrumGovernorVotesQuorumFractionUpgradeable.sol";


contract SecurityCouncilNomineeElectionGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorVotesUpgradeable,
    SecurityCouncilNomineeElectionGovernorCounting,
    ArbitrumGovernorVotesQuorumFractionUpgradeable,
    GovernorSettingsUpgradeable,
    OwnableUpgradeable
{
    // todo: set these in the constructor / initializer
    uint256 public targetNomineeCount;
    Cohort public firstCohort;
    uint256 public firstNominationStartTime;
    uint256 public nominationFrequency;
    ISecurityCouncilManager public securityCouncilManager;

    // number of nominee selection proposals that have been created
    uint256 public proposalCount;

    // maps proposalId to map of address to bool indicating whether the candidate is a contender for nomination
    mapping(uint256 => mapping(address => bool)) public contenders;

    /// @notice Allows the owner to make calls from the governor
    /// @dev    See {L2ArbitrumGovernor-relay}
    function relay(address target, uint256 value, bytes calldata data)
        external
        virtual
        override
        onlyOwner
    {
        AddressUpgradeable.functionCallWithValue(target, data, value);
    }

    // override propose to revert
    function propose(
        address[] memory,
        uint256[] memory,
        bytes[] memory,
        string memory
    ) public virtual override returns (uint256) {
        revert("Proposing is not allowed, call createElection instead");
    }

    // proposal threshold is 0 because we call propose via createElection
    function proposalThreshold() public view virtual override(GovernorSettingsUpgradeable, GovernorUpgradeable) returns (uint256) {
        return 0;
    }

    function createElection() external returns (uint256 proposalIndex, uint256 proposalId) {
        require(block.timestamp >= firstNominationStartTime + nominationFrequency * proposalCount, "Not enough time has passed since the last election");

        // create a proposal with dummy address and value
        // make the calldata abi.encode(proposalIndex)
        // this is necessary because we need to know the proposalIndex in order to know which cohort a proposal is for when we execute

        proposalIndex = proposalCount;
        proposalCount++;

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encode(proposalIndex);

        proposalId = GovernorUpgradeable.propose(targets, values, calldatas, proposalIndexToDescription(proposalIndex));
    }

    function _execute(
        uint256 /* proposalId */,
        address[] memory /* targets */,
        uint256[] memory /* values */,
        bytes[] memory calldatas,
        bytes32 /*descriptionHash*/
    ) internal virtual override {
        uint256 proposalIndex = abi.decode(calldatas[0], (uint256));
        uint256 proposalId = proposalIndexToProposalId(proposalIndex);

        uint256 numNominated = nomineeCount(proposalId);

        if (numNominated > targetNomineeCount) {
            // todo:
            // call the SecurityCouncilMemberElectionGovernor to execute the election
            // the SecurityCouncilMemberElectionGovernor will call back into this contract to look up nominees
            return;
        }

        address[] memory nominees;
        if (numNominated < targetNomineeCount) {
            // todo: randomly select some number of candidates from current cohort to add to the nominees
            // nominees = ...
        }
        else {
            nominees = SecurityCouncilNomineeElectionGovernorCounting.nominees(proposalId);
        }
        
        // call the SecurityCouncilManager to switch out the security council members
        securityCouncilManager.executeElectionResult(nominees, proposalIndexToCohort(proposalIndex));
    }

    function addContender(uint256 proposalId, address account) external {
        ProposalState state = state(proposalId);
        require(state == ProposalState.Active, "Proposal is not active");

        // todo: check to make sure the candidate is eligible (not part of the other cohort, etc.)

        contenders[proposalId][account] = true;
    }

    function _isContender(uint256 proposalId, address candidate) internal view virtual override returns (bool) {
        return contenders[proposalId][candidate];
    }

    function proposalIndexToCohort(uint256 proposalIndex) public view returns (Cohort) {
        return Cohort((uint256(firstCohort) + proposalIndex) % 2);
    }

    function proposalIndexToDescription(uint256 proposalIndex) public pure returns (string memory) {
        return string.concat("Nominee Selection #", StringsUpgradeable.toString(proposalIndex));
    }

    function proposalIndexToProposalId(uint256 proposalIndex) public pure returns (uint256) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encode(proposalIndex);

        return hashProposal(targets, values, calldatas, keccak256(bytes(proposalIndexToDescription(proposalIndex))));
    }
}
