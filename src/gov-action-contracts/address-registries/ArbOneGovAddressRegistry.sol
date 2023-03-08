// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./ArbOneGovAddressRegistryInterfaces.sol";

contract ArbOneGovAddressRegistry is IArbOneGovAddressRegistry {
    IL2ArbitrumGoverner public immutable coreGov;
    IL2ArbitrumGoverner public immutable treasuryGov;
    IFixedDelegateErc20Wallet public immutable treasuryWallet;

    constructor(
        IL2ArbitrumGoverner _coreGov,
        IL2ArbitrumGoverner _treasuryGov,
        IFixedDelegateErc20Wallet _treasuryWallet
    ) {
        require(
            _treasuryWallet.owner() == _treasuryGov.timelock(),
            "ArbOneGovAddressRegistry: treasury gov timelock must own treasuryWallet"
        );
        coreGov = _coreGov;
        treasuryGov = _treasuryGov;
        treasuryWallet = _treasuryWallet;
    }

    function coreGovTimelock() external view returns (IArbitrumTimelock) {
        return IArbitrumTimelock(coreGov.timelock());
    }

    function treasuryGovTimelock() external view returns (IArbitrumTimelock) {
        return IArbitrumTimelock(treasuryGov.timelock());
    }

    function l2ArbitrumToken() external view returns (IL2ArbitrumToken) {
        IL2ArbitrumGoverner(address(coreGov)).token();
    }
}
