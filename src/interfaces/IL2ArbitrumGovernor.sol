// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./IL2ArbitrumToken.sol";

interface IL2ArbitrumGoverner {
    // token() is inherited from GovernorVotesUpgradeable
    function token() external view returns (IL2ArbitrumToken);
    function relay(address target, uint256 value, bytes calldata data) external;
    function timelock() external view returns (address);
    function votingDelay() external view returns (uint256);
    function setVotingDelay(uint256 newVotingDelay) external;
    function votingPeriod() external view returns (uint256);
    function setVotingPeriod(uint256 newVotingPeriod) external;
    function EXCLUDE_ADDRESS() external view returns (address);
    function owner() external view returns (address);
    function proposalThreshold() external view returns (uint256);
    function setProposalThreshold(uint256 newProposalThreshold) external;
}
