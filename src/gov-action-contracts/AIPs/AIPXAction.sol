// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {
    ProxyAdmin,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    SecurityCouncilNomineeElectionGovernor,
    GovernorSettingsUpgradeable
} from "../../security-council-mgmt/governors/SecurityCouncilNomineeElectionGovernor.sol";

contract AIPXAction {
    address public immutable proxyAdmin;
    address public immutable nomineeElectionGovernorProxy;
    address public immutable newNomineeElectionGovernorImplementation;
    uint256 public immutable votingDelay;

    constructor(
        address _proxyAdmin,
        address _nomineeElectionGovernorProxy,
        address _newNomineeElectionGovernorImplementation,
        uint256 _votingDelay
    ) {
        proxyAdmin = _proxyAdmin;
        nomineeElectionGovernorProxy = _nomineeElectionGovernorProxy;
        newNomineeElectionGovernorImplementation = _newNomineeElectionGovernorImplementation;
        votingDelay = _votingDelay;
    }

    function perform() external {
        // upgrade implementation
        ProxyAdmin(proxyAdmin).upgrade(
            TransparentUpgradeableProxy(payable(nomineeElectionGovernorProxy)),
            newNomineeElectionGovernorImplementation
        );

        // set the voting delay
        SecurityCouncilNomineeElectionGovernor(payable(nomineeElectionGovernorProxy)).relay(
            nomineeElectionGovernorProxy,
            0,
            abi.encodeWithSelector(GovernorSettingsUpgradeable.setVotingDelay.selector, votingDelay)
        );
    }
}
