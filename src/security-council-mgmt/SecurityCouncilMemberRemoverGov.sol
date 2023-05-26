// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../L2ArbitrumGovernor.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ISecurityCouncilManager.sol";
import "./SecurityCouncilMgmtUtils.sol";

contract SecurityCouncilMemberRemoverGov is L2ArbitrumGovernor, AccessControlUpgradeable {
    ISecurityCouncilManager public securityCouncilManager;
    bytes32 public constant PROPSER_ROLE = keccak256("PROPOSER");

    constructor() {
        _disableInitializers();
    }

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

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(IGovernorUpgradeable, GovernorUpgradeable) returns (uint256) {
        revert("SecurityCouncilMemberRemoverGov: generic propose not supported");
    }

    function proposeRemoveMember(address memberToRemove, string memory description)
        public
        onlyRole(PROPSER_ROLE)
        returns (uint256)
    {
        

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
