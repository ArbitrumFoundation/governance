// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../interfaces/IArbitrumTimelock.sol";
import "../../interfaces/IFixedDelegateErc20Wallet.sol";
import "../../interfaces/IL2ArbitrumToken.sol";
import "../../interfaces/IL2ArbitrumGovernor.sol";
import "../../interfaces/IArbitrumDAOConstitution.sol";
import "../../security-council-mgmt/interfaces/ISecurityCouncilManager.sol";
import "../../security-council-mgmt/interfaces/ISecurityCouncilNomineeElectionGovernor.sol";
import "../../security-council-mgmt/interfaces/ISecurityCouncilMemberElectionGovernor.sol";

interface ICoreGovTimelockGetter {
    function coreGovTimelock() external view returns (IArbitrumTimelock);
}

interface ICoreGovGetter {
    function coreGov() external view returns (IL2ArbitrumGoverner);
}

interface ITreasuryGovTimelockGetter {
    function treasuryGovTimelock() external view returns (IArbitrumTimelock);
}

interface ITreasuryGovGetter {
    function treasuryGov() external view returns (IL2ArbitrumGoverner);
}

interface IDaoTreasuryGetter {
    function treasuryWallet() external view returns (IFixedDelegateErc20Wallet);
}

interface IL2ArbitrumTokenGetter {
    function l2ArbitrumToken() external view returns (IL2ArbitrumToken);
}

interface IArbitrumDAOConstitutionGetter {
    function arbitrumDAOConstitution() external view returns (IArbitrumDAOConstitution);
}

interface IGovProxyAdminGetter {
    function govProxyAdmin() external view returns (ProxyAdmin);
}

interface ISecurityCouncilGetters {
    function securityCouncilManager() external view returns (ISecurityCouncilManager);
    function scNomineeElectionGovernor()
        external
        view
        returns (ISecurityCouncilNomineeElectionGovernor);
    function scMemberElectionGovernor()
        external
        view
        returns (ISecurityCouncilMemberElectionGovernor);
}

interface IL2AddressRegistry is
    ICoreGovGetter,
    ICoreGovTimelockGetter,
    ITreasuryGovTimelockGetter,
    IDaoTreasuryGetter,
    ITreasuryGovGetter,
    IL2ArbitrumTokenGetter,
    IArbitrumDAOConstitutionGetter,
    IGovProxyAdminGetter,
    ISecurityCouncilGetters
{}
