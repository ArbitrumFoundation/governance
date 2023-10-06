// SPDX-Licens©e-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../L2ArbitrumGovernor.sol";
import "../../ArbitrumTimelock.sol";
import "../../UpgradeExecutor.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/// @notice Parameters for deployment
struct DeployParams {
    address _governanceToken; // Address of IVotesUpgradeable token deployed on the governance chain
    address _govChainUpExec; // Address of governance UpgradeExecutor deployed on the governance chain
    address _govChainProxyAdmin; // Address of UpgradeExecutor deployed on the governance chain
    uint256 _proposalThreshold; // Number of votes required to submit a proposal
    uint256 _votingPeriod; // Time period in blocks during which voting for a proposal occurs
    uint256 _votingDelay; // Delay in blocks after a proposal is submitted before voting begins
    uint256 _minTimelockDelay; // Delay in seconds after proposal passes before it can be executed
    uint64 _minPeriodAfterQuorum; // Minimum voting time in blocks after a quorum is reached
    uint256 _coreQuorumThreshold; // Required quorum for proposal to pass; has 10k denominator
}
/// @title Factory that deploys governance chain contracts for cross chain governance
/// @notice Requries an UpgradeExecutor, a ProxyAdmin, and a governance token
/// that implements IVotesUpgradeable to already be deployed on the governance chain.
/// To be executed prior to ParentChainGovFactory on the parent chain.

contract GovernanceChainGovFactory is Ownable {
    bool private done = false;

    event Deployed(ArbitrumTimelock coreTimelock, L2ArbitrumGovernor coreGoverner);

    error AlreadyExecuted();
    error NotAContract(address _address);
    error NotAGovernanceToken(address _address);

    address public govLogic;
    address public timelockLogic;

    constructor() {
        govLogic = address(new L2ArbitrumGovernor());
        timelockLogic = address(new ArbitrumTimelock());
    }

    function deployStep1(DeployParams memory params)
        public
        virtual
        onlyOwner
        returns (ArbitrumTimelock, L2ArbitrumGovernor)
    {
        if (done) {
            revert AlreadyExecuted();
        }
        done = true;
        // sanity checks:
        // provided upgrade executor is a contract
        if (!Address.isContract(params._govChainUpExec)) {
            revert NotAContract(params._govChainUpExec);
        }
        // provided proxy admin is a contract
        if (!Address.isContract(params._govChainProxyAdmin)) {
            revert NotAContract(params._govChainProxyAdmin);
        }
        // provided governance token has an expected IVotesUpgradeable method
        try IVotesUpgradeable(params._governanceToken).getPastTotalSupply(0) {}
        catch (bytes memory) {
            revert NotAGovernanceToken(params._governanceToken);
        }
        // end of santiy checks

        // deploy and init the timelock
        ArbitrumTimelock coreTimelock =
            deployTimelock(ProxyAdmin(params._govChainProxyAdmin), timelockLogic);
        coreTimelock.initialize(params._minTimelockDelay, new address[](0), new address[](0));

        // deploy and init the core governor
        L2ArbitrumGovernor coreGov =
            deployGovernor(ProxyAdmin(params._govChainProxyAdmin), govLogic);
        coreGov.initialize({
            _token: IVotesUpgradeable(params._governanceToken),
            _timelock: coreTimelock,
            _owner: params._govChainUpExec,
            _votingDelay: params._votingDelay,
            _votingPeriod: params._votingPeriod,
            _quorumNumerator: params._coreQuorumThreshold,
            _proposalThreshold: params._proposalThreshold,
            _minPeriodAfterQuorum: params._minPeriodAfterQuorum
        });

        // governor can submit proposals to timelock propose
        coreTimelock.grantRole(coreTimelock.PROPOSER_ROLE(), address(coreGov));
        // upgrade executor can cancel
        coreTimelock.grantRole(coreTimelock.CANCELLER_ROLE(), params._govChainUpExec);

        // anyone is allowed to execute on the timelock
        coreTimelock.grantRole(coreTimelock.EXECUTOR_ROLE(), address(0));

        // after initialisation, give admin roles to the upgrade executor
        // and revoke admin roles from the timelock and from this deployer
        coreTimelock.grantRole(coreTimelock.TIMELOCK_ADMIN_ROLE(), params._govChainUpExec);
        coreTimelock.revokeRole(coreTimelock.TIMELOCK_ADMIN_ROLE(), address(coreTimelock));
        coreTimelock.revokeRole(coreTimelock.TIMELOCK_ADMIN_ROLE(), address(this));

        emit Deployed(coreTimelock, coreGov);
        return (coreTimelock, coreGov);
    }

    function deployGovernor(ProxyAdmin _proxyAdmin, address _govChainGovernorLogic)
        internal
        returns (L2ArbitrumGovernor)
    {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _govChainGovernorLogic,
            address(_proxyAdmin),
            bytes("")
        );
        return L2ArbitrumGovernor(payable(address(proxy)));
    }

    function deployTimelock(ProxyAdmin _proxyAdmin, address _govChainTimelockLogic)
        internal
        returns (ArbitrumTimelock)
    {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            _govChainTimelockLogic,
            address(_proxyAdmin),
            bytes("")
        );
        return ArbitrumTimelock(payable(address(proxy)));
    }
}
