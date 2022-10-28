// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./L2ArbitrumToken.sol";
import "./L2ArbitrumGovernor.sol";
import "./ArbitrumTimelock.sol";

// @openzeppelin-contracts-upgradeable doesn't contain transparent proxies
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @title Factory contract that deploys the L2 components for Arbitrum governance
contract L2GovernanceFactory {
    event Deployed(
        L2ArbitrumToken token, ArbitrumTimelock timelock, L2ArbitrumGovernor governor, ProxyAdmin proxyAdmin
    );

    function deploy(
        uint256 _minTimelockDelay,
        address _l1TokenAddress,
        address _l2TokenLogic,
        uint256 _initialSupply,
        address _owner,
        address _l2TimeLockLogic,
        address _l2GovernorLogic
    )
        external
        returns (L2ArbitrumToken token, L2ArbitrumGovernor gov, ArbitrumTimelock timelock, ProxyAdmin proxyAdmin)
    {
        // CHRIS: TODO: we dont want the owner of the proxy admin to be this address!
        // CHRIS: TODO: in both this and the L1gov fac
        proxyAdmin = new ProxyAdmin();

        token = deployToken(proxyAdmin, _l2TokenLogic);
        token.initialize(_l1TokenAddress, _initialSupply, _owner);

        timelock = deployTimelock(proxyAdmin, _l2TimeLockLogic);
        address[] memory proposers;
        address[] memory executors;
        timelock.initialize(_minTimelockDelay, proposers, executors);

        gov = deployGovernor(proxyAdmin, _l2GovernorLogic);
        gov.initialize(token, timelock);

        // the timelock itself and deployer are admins
        // CHRIS: TODO: set the same for the l1 contract?
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(gov));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(timelock));
        timelock.revokeRole(timelock.TIMELOCK_ADMIN_ROLE(), address(this));

        emit Deployed(token, timelock, gov, proxyAdmin);
    }

    function deployToken(ProxyAdmin _proxyAdmin, address _l2TokenLogic) internal returns (L2ArbitrumToken token) {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(_l2TokenLogic, address(_proxyAdmin), bytes(""));
        token = L2ArbitrumToken(address(proxy));
    }

    function deployGovernor(ProxyAdmin _proxyAdmin, address _l2GovernorLogic)
        internal
        returns (L2ArbitrumGovernor gov)
    {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(_l2GovernorLogic, address(_proxyAdmin), bytes(""));
        gov = L2ArbitrumGovernor(payable(address(proxy)));
    }

    function deployTimelock(ProxyAdmin _proxyAdmin, address _l2TimelockLogic)
        internal
        returns (ArbitrumTimelock timelock)
    {
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(_l2TimelockLogic, address(_proxyAdmin), bytes(""));
        timelock = ArbitrumTimelock(payable(address(proxy)));
    }
}
