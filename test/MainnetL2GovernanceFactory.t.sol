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

    function testDeploy() public {
        DeployCoreParams memory deployParams = DeployCoreParams({
            _l2MinTimelockDelay: l2MinTimelockDelay,
            _l1Token: l1Token,
            _l2TokenInitialSupply: l2TokenInitialSupply,
            _l2TokenOwner: l2TokenOwner,
            _l2UpgradeExecutors: l2UpgradeExecutors,
            _votingPeriod: votingPeriod,
            _votingDelay: votingDelay,
            _coreQuorumThreshold: coreQuorumThreshold,
            _treasuryQuorumThreshold: treasuryQuorumThreshold,
            _proposalThreshold: proposalThreshold,
            _minPeriodAfterQuorum: minPeriodAfterQuorum
        });

        MainnetL2GovernanceFactory l2GovernanceFactory = new MainnetL2GovernanceFactory();
        vm.expectRevert("ONLY_DEPLOYMAINNET");
        l2GovernanceFactory.deploy(deployParams);

        vm.startPrank(someRando);
        vm.expectRevert("NOT_DEPLOYER");
        l2GovernanceFactory.deployMainnet();

        vm.stopPrank();
        l2GovernanceFactory.deployMainnet();
        assertTrue(true, "deployMainnet didn't revert");

    }
}
