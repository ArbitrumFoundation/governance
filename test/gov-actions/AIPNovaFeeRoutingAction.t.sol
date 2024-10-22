// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

// this test is meant to be run with a nova fork url

import "forge-std/Test.sol";

import "../../src/gov-action-contracts/AIPs/AIPNovaFeeRoutingAction.sol";
import "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";

contract AIPNovaFeeRoutingActionTest is Test {
    UpgradeExecutor constant upExec = UpgradeExecutor(0x86a02dD71363c440b21F4c0E5B2Ad01Ffe1A7482);

    function testAction() public {
        if (!isFork()) {
            return;
        }

        AIPNovaFeeRoutingAction action = new AIPNovaFeeRoutingAction();

        // before we run the action, we need to make sure the upgrade executor has at least this much ETH
        vm.deal(address(upExec), 3*action.fullWeight());

        vm.prank(0xf7951D92B0C345144506576eC13Ecf5103aC905a);
        upExec.execute(address(action), abi.encodeWithSignature("perform()"));

        // make sure the new recipients are set

        address[1] memory expectedL1SurplusRecipients = [0xd9a2e0E5d7509F0BF1B2d33884F8C1b4D4490879];
        uint256[1] memory expectedL1SurplusWeights = [uint(10_000)];

        assertEq(IRewardDistributor(action.novaL1SurplusFeeDistr()).currentRecipientGroup(), keccak256(abi.encodePacked(expectedL1SurplusRecipients)));
        assertEq(IRewardDistributor(action.novaL1SurplusFeeDistr()).currentRecipientWeights(), keccak256(abi.encodePacked(expectedL1SurplusWeights)));
        assertEq(IRewardDistributor(action.novaL2SurplusFeeDistr()).currentRecipientGroup(), keccak256(abi.encodePacked(expectedL1SurplusRecipients)));
        assertEq(IRewardDistributor(action.novaL2SurplusFeeDistr()).currentRecipientWeights(), keccak256(abi.encodePacked(expectedL1SurplusWeights)));


        address[7] memory expectedBaseFeeRecipients = [
            0xd9a2e0E5d7509F0BF1B2d33884F8C1b4D4490879, // nova to l1 router
            0xD0749b3e537Ed52DE4e6a3Ae1eB6fc26059d0895, // rest are same as current
            0x41C327d5fc9e29680CcD45e5E52446E0DB3DAdFd,
            0x02C2599aa929e2509741b44F3a13029745aB1AB2,
            0xA221f29236996BDEfA5C585acdD407Ec84D78447,
            0x0fB1f1a31429F1A90a19Ab5486a6DFb384179641,
            0xb814441ed86e98e8B83d31eEC095e4a5A36Fc3c2
        ];

        uint256[7] memory expectedBaseFeeWeights = [
            uint256(8000),
            uint256(375),
            uint256(373),
            uint256(373),
            uint256(373),
            uint256(373),
            uint256(133)
        ];

        assertEq(IRewardDistributor(action.novaL2BaseFeeDistr()).currentRecipientGroup(), keccak256(abi.encodePacked(expectedBaseFeeRecipients)));
        assertEq(IRewardDistributor(action.novaL2BaseFeeDistr()).currentRecipientWeights(), keccak256(abi.encodePacked(expectedBaseFeeWeights)));
    }
}