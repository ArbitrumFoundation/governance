// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/L2GovernanceFactory.sol";
import "../src/MainnetL2GovernanceFactory.sol";

import "../src/L2ArbitrumGovernor.sol";
import "../src/UpgradeExecutor.sol";
import "../src/ArbitrumTimelock.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract MainnetL2GovernanceFactoryTest is Test {
    // token
    address l2TokenOwner = address(2);
    address l1Token = address(1);
    uint256 l2TokenInitialSupply = 43;

    // timelock
    uint256 l2MinTimelockDelay = 42;

    // govs
    uint256 votingPeriod = 44;
    uint256 votingDelay = 45;
    uint256 coreQuorumThreshold = 4;
    uint256 treasuryQuorumThreshold = 3;
    uint256 proposalThreshold = 5e6;
    uint64 minPeriodAfterQuorum = 41;

    address[] l2UpgradeExecutors = [address(4), address(5)];

    address[] addressArrayStub = [address(777), address(888)];

    address someRando = address(3);
    address upgradeProposer = address(1234);

    function testDeploy() public {
        DeployCoreParams memory deployParams = DeployCoreParams({
            _l2MinTimelockDelay: l2MinTimelockDelay,
            _l1Token: l1Token,
            _l2TokenInitialSupply: l2TokenInitialSupply,
            _l2TokenOwner: l2TokenOwner,
            _votingPeriod: votingPeriod,
            _votingDelay: votingDelay,
            _coreQuorumThreshold: coreQuorumThreshold,
            _treasuryQuorumThreshold: treasuryQuorumThreshold,
            _proposalThreshold: proposalThreshold,
            _minPeriodAfterQuorum: minPeriodAfterQuorum,
            _upgradeProposer: upgradeProposer
        });

        address _coreTimelockLogic = address(new ArbitrumTimelock());
        address _coreGovernorLogic = address(new L2ArbitrumGovernor());
        address _treasuryTimelockLogic = address(new ArbitrumTimelock());
        address _treasuryLogic = address(new FixedDelegateErc20Wallet());
        address _treasuryGovernorLogic = address(new L2ArbitrumGovernor());
        address _l2TokenLogic = address(new L2ArbitrumToken());
        address _upgradeExecutorLogic = address(new UpgradeExecutor());

        MainnetL2GovernanceFactory l2GovernanceFactory = new MainnetL2GovernanceFactory(
            _coreTimelockLogic,
            _coreGovernorLogic,
            _treasuryTimelockLogic,
            _treasuryLogic,
            _treasuryGovernorLogic,
            _l2TokenLogic,
            _upgradeExecutorLogic
        );
        vm.expectRevert("MainnetL2GovernanceFactory: can only use deployStep1Mainnet");
        l2GovernanceFactory.deployStep1(deployParams);

        vm.startPrank(someRando);
        vm.expectRevert("Ownable: caller is not the owner");
        l2GovernanceFactory.deployStep1Mainnet();

        vm.stopPrank();
        l2GovernanceFactory.deployStep1Mainnet();
        assertTrue(true, "deployStep1Mainnet didn't revert");
    }
}
