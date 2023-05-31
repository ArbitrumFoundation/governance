// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/IGovernorUpgradeable.sol";

import "./SecurityCouncilManager.sol";
import "./SecurityCouncilNominationsGovernor.sol";

// todo: constructor or initializer
contract SecurityCouncilNominationsManager {
    // todo: set these in the constructor / initializer
    uint256 public targetNomineeCount;
    Cohort public firstCohort;
    uint256 public firstNominationStartTime;
    uint256 public nominationFrequency;
    SecurityCouncilManager public securityCouncilManager;
    SecurityCouncilNominationsGovernor public nominationsGovernor;

    // number of nomination elections that have been created
    uint256 public nominationsCount;

    // maps electionId to mapping of candidates up for nomination
    mapping(uint256 => mapping(address => bool)) public isCandidateUpForNomination;

    // maps NominationsManager's electionId to NominationsGovernor's proposalId
    mapping(uint256 => uint256) public electionIdToProposalId;

    modifier onlyGovernor {
        require(msg.sender == address(nominationsGovernor), "Only the governor can call this");
        _;
    }

    function createElection() external returns (uint256 electionId) {
        require(block.timestamp >= firstNominationStartTime + nominationFrequency * nominationsCount, "Not enough time has passed since the last election");

        electionId = nominationsCount;

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(this);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(this.executeFromGovernor.selector, electionId);

        // TODO: set the description to something meaningful
        uint256 proposalId = nominationsGovernor.propose(
            targets,
            values,
            calldatas,
            "TODO"
        );

        electionIdToProposalId[electionId] = proposalId;

        nominationsCount++;
    }

    function nominateCandidate(uint256 electionId, address account) external {
        IGovernorUpgradeable.ProposalState state = nominationsGovernor.state(electionIdToProposalId[electionId]);
        require(state == IGovernorUpgradeable.ProposalState.Active, "Proposal is not active");

        // todo: check to make sure the candidate is eligible (not part of the other cohort, etc.)

        isCandidateUpForNomination[electionId][account] = true;
    }

    // vote has finished, some number of candidates have been nominated
    // governor contract calls this function
    function executeFromGovernor(uint256 electionId) external onlyGovernor {
        uint256 numNominated = nominationsGovernor.successfullyNominatedCandidatesCount(electionIdToProposalId[electionId]);

        if (numNominated > targetNomineeCount) {
            // TODO:
            // call some ElectionsManager to start the election with the nominated candidates
            // the ElectionsManager or ElectionsGovernor will call either this contract or the NominationsGovernor to check which candidates are eligible when someone casts a vote
            // ... or we can read out the entire list of successfullyNominatedCandidates and pass that along, but the list could be pretty long

            // or maybe we don't use another manager contract at all, just have this contract manage the nominations governor as well as the phase 2&3 governor
            return;
        }

        address[] memory nominees;
        if (numNominated < targetNomineeCount) {
            // todo: randomly select some number of candidates from current cohort to add to the nominees
            // nominees = ...
        }
        else {
            nominees = nominationsGovernor.successfullyNominatedCandidates(electionIdToProposalId[electionId]);
        }
        
        // call the SecurityCouncilManager to switch out the security council members
        securityCouncilManager.executeElectionResult(nominees, cohortOfElection(electionId));
    }

    function cohortOfElection(uint256 electionId) public view returns (Cohort) {
        return Cohort((uint256(firstCohort) + electionId) % 2);
    }
}