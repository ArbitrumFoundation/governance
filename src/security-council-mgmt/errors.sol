// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./interfaces/ISecurityCouncilManager.sol";

// generic
error ZeroAddress();
error NotAContract(address account);

// security council cohorts
error NotAMember(address member);
error MemberInCohort(address member, Cohort cohort);
error CohortFull(Cohort cohort);
error InvalidNewCohortLength(address[] cohort);

// security council data
error MaxSecurityCouncils(uint256 securityCouncilCount);
error SecurityCouncilZeroChainID(SecurityCouncilData securiyCouncilData);
error SecurityCouncilNotInRouter(SecurityCouncilData securiyCouncilData);
error SecurityCouncilNotInManager(SecurityCouncilData securiyCouncilData);
error SecurityCouncilAlreadyInRouter(SecurityCouncilData securiyCouncilData);
