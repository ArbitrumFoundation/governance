// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "./L2AddressRegistryInterfaces.sol";

contract L2AddressRegistry is IL2AddressRegistry {
    IL2ArbitrumGoverner public immutable coreGov;
    IL2ArbitrumGoverner public immutable treasuryGov;
    IFixedDelegateErc20Wallet public immutable treasuryWallet;
    IArbitrumDAOConstitution public immutable arbitrumDAOConstitution;
    ProxyAdmin public immutable govProxyAdmin;
    ISecurityCouncilNomineeElectionGovernor public immutable scNomineeElectionGovernor;

    constructor(
        IL2ArbitrumGoverner _coreGov,
        IL2ArbitrumGoverner _treasuryGov,
        IFixedDelegateErc20Wallet _treasuryWallet,
        IArbitrumDAOConstitution _arbitrumDAOConstitution,
        ProxyAdmin _govProxyAdmin,
        ISecurityCouncilNomineeElectionGovernor _scNomineeElectionGovernor
    ) {
        require(
            _treasuryWallet.owner() == _treasuryGov.timelock(),
            "L2AddressRegistry: treasury gov timelock must own treasuryWallet"
        );
        require(
            _arbitrumDAOConstitution.owner() == _coreGov.owner(),
            "L2AddressRegistry DAO must own ArbitrumDAOConstitution"
        );
        coreGov = _coreGov;
        treasuryGov = _treasuryGov;
        treasuryWallet = _treasuryWallet;
        arbitrumDAOConstitution = _arbitrumDAOConstitution;
        require(
            _govProxyAdmin.getProxyAdmin(TransparentUpgradeableProxy(payable(address(_coreGov))))
                == address(_govProxyAdmin),
            "GovProxyAdmin must be proxy admin of the core governor"
        );
        govProxyAdmin = _govProxyAdmin;
        scNomineeElectionGovernor = _scNomineeElectionGovernor;
    }

    function coreGovTimelock() external view returns (IArbitrumTimelock) {
        return IArbitrumTimelock(coreGov.timelock());
    }

    function treasuryGovTimelock() external view returns (IArbitrumTimelock) {
        return IArbitrumTimelock(treasuryGov.timelock());
    }

    function l2ArbitrumToken() external view returns (IL2ArbitrumToken) {
        return IL2ArbitrumGoverner(address(coreGov)).token();
    }

    function scMemberElectionGovernor()
        external
        view
        returns (ISecurityCouncilMemberElectionGovernor)
    {
        return scNomineeElectionGovernor.securityCouncilMemberElectionGovernor();
    }

    function securityCouncilManager() external view returns (ISecurityCouncilManager) {
        return scNomineeElectionGovernor.securityCouncilManager();
    }
}
