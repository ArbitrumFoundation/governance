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
import {IArbitrumDAOConstitution} from "../../interfaces/IArbitrumDAOConstitution.sol";

contract NomineeGovernorV2UpgradeActionTemplate {
    address public immutable proxyAdmin;
    address public immutable nomineeElectionGovernorProxy;
    address public immutable newNomineeElectionGovernorImplementation;
    uint256 public immutable votingDelay;

    address public immutable constitution;
    bytes32 public immutable newConstitutionHash;

    constructor(
        address _proxyAdmin,
        address _nomineeElectionGovernorProxy,
        address _newNomineeElectionGovernorImplementation,
        uint256 _votingDelay,
        address _constitution,
        bytes32 _newConstitutionHash
    ) {
        proxyAdmin = _proxyAdmin;
        nomineeElectionGovernorProxy = _nomineeElectionGovernorProxy;
        newNomineeElectionGovernorImplementation = _newNomineeElectionGovernorImplementation;
        votingDelay = _votingDelay;
        constitution = _constitution;
        newConstitutionHash = _newConstitutionHash;
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
            abi.encodeCall(GovernorSettingsUpgradeable.setVotingDelay, (votingDelay))
        );

        // set the new constitution hash
        IArbitrumDAOConstitution(constitution).setConstitutionHash(newConstitutionHash);
    }
}

contract NomineeGovernorV2UpgradeAction is NomineeGovernorV2UpgradeActionTemplate {
    constructor() NomineeGovernorV2UpgradeActionTemplate(
        0xdb216562328215E010F819B5aBe947bad4ca961e,
        0x8a1cDA8dee421cD06023470608605934c16A05a0,
        address(new SecurityCouncilNomineeElectionGovernor()),
        50400,
        0x1D62fFeB72e4c360CcBbacf7c965153b00260417,
        0xe794b7d0466ffd4a33321ea14c307b2de987c3229cf858727052a6f4b8a19cc1
    ) {}
}
