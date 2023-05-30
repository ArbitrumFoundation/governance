// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../L2ArbitrumGovernor.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ISecurityCouncilManager.sol";
import "./SecurityCouncilMgmtUtils.sol";
import "./interfaces/ISecurityCouncilMemberRemoverGov.sol";

/// @notice Governance for proposing removal of a single security council member due to
/// unforseen circumstances, as described in the DAO constitution.
/// The 9 of 12 emergency council submits the removal proposal (giving implicit approval),
/// and the DAO votes on it.
contract SecurityCouncilMemberRemoverGov is
    L2ArbitrumGovernor,
    AccessControlUpgradeable,
    ISecurityCouncilMemberRemoverGov
{
    ISecurityCouncilManager public securityCouncilManager;
    bytes32 public constant PROPSER_ROLE = keccak256("PROPOSER");

    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract
    /// @param _proposer The address that can propose a removal (9 of 12 emergency council)
    /// @param _securityCouncilManager The address of the security council manager
    /// @param _token The address of the governance token
    /// @param _timelock A time lock for proposal execution
    /// @param _owner The DAO (Upgrade Executor); admin over proposal role
    /// @param _votingDelay The delay between a proposal submission and voting starts
    /// @param _votingPeriod The period for which the vote lasts
    /// @param _quorumNumerator The proportion of the circulating supply required to reach a quorum
    /// @param _proposalThreshold The number of delegated votes required to create a proposal
    /// @param _minPeriodAfterQuorum The minimum number of blocks available for voting after the quorum is reached
    function initialize(
        address _proposer,
        ISecurityCouncilManager _securityCouncilManager,
        IVotesUpgradeable _token,
        TimelockControllerUpgradeable _timelock,
        address _owner,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumNumerator,
        uint256 _proposalThreshold,
        uint64 _minPeriodAfterQuorum
    ) external initializer {
        require(
            _proposer != address(0), "SecurityCouncilMemberRemoverGov: non-zero proposer address"
        );
        require(
            Address.isContract(address(_securityCouncilManager)),
            "SecurityCouncilMemberRemoverGov: invalid _securityCouncilManager"
        );
        securityCouncilManager = _securityCouncilManager;
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(PROPSER_ROLE, _proposer);
        this.initialize(
            _token,
            _timelock,
            _owner,
            _votingDelay,
            _votingPeriod,
            _quorumNumerator,
            _proposalThreshold,
            _minPeriodAfterQuorum
        );
    }

    /// @notice public propose method is overridden and simply revers.
    /// Removal proposals must go through the proposeRemoveMember method
    function propose(
        address[] memory __,
        uint256[] memory ___,
        bytes[] memory ____,
        string memory _____
    ) public override(IGovernorUpgradeable, GovernorUpgradeable) returns (uint256) {
        revert("SecurityCouncilMemberRemoverGov: generic propose not supported");
    }

    /// @notice Propose a removal of a security council member. Callable only by the 9 of 12 emergency council
    /// @param memberToRemove The address of the member to remove
    /// @param description The description of the proposal (i.e., explanation of why member is should be removed)
    function proposeRemoveMember(address memberToRemove, string memory description)
        external
        onlyRole(PROPSER_ROLE)
        returns (uint256)
    {
        require(
            SecurityCouncilMgmtUtils.isInArray(
                memberToRemove, securityCouncilManager.getMarchCohort()
            )
                || SecurityCouncilMgmtUtils.isInArray(
                    memberToRemove, securityCouncilManager.getSeptemberCohort()
                ),
            "SecurityCouncilMemberRemoverGov: memberToRemove is not a member"
        );

        address[] memory targets;
        targets[0] = address(securityCouncilManager);

        uint256[] memory values;
        values[0] = 0;

        bytes memory removalCallData =
            abi.encodeWithSelector(ISecurityCouncilManager.removeMember.selector, memberToRemove);
        bytes[] memory callDatas;
        callDatas[0] = removalCallData;

        GovernorUpgradeable.propose(targets, values, callDatas, description);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, L2ArbitrumGovernor)
        returns (bool)
    {
        return L2ArbitrumGovernor.supportsInterface(interfaceId);
    }
}
