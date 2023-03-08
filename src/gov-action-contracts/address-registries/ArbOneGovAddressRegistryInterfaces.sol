// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IArbitrumTimelock {
    function cancel(bytes32 id) external;
    function scheduleBatch(
        address[] calldata target,
        uint256[] calldata payloads,
        bytes[] calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) external;
    function getMinDelay() external view returns (uint256 duration);
}

interface IOwnable {
    function owner() external view returns (address);
}

interface IL2ArbitrumToken is IERC20Upgradeable {
    function mint(address recipient, uint256 amount) external;
}

interface IFixedDelegateErc20Wallet is IOwnable {
    function transfer(address _token, address _to, uint256 _amount) external returns (bool);
}

interface IL2ArbitrumGoverner {
    // token() is inherited from GovernorVotesUpgradeable
    function token() external view returns (IL2ArbitrumToken);
    function relay(address target, uint256 value, bytes calldata data) external;
    function timelock() external view returns (address);
}

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

interface IArbOneGovAddressRegistry is
    ICoreGovGetter,
    ICoreGovTimelockGetter,
    ITreasuryGovTimelockGetter,
    IDaoTreasuryGetter,
    ITreasuryGovGetter,
    IL2ArbitrumTokenGetter
{}
