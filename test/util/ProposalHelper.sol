// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {
    CreateL2ArbSysProposal,
    IFixedDelegateErc20Wallet
} from "script/helpers/CreateL2ArbSysProposal.sol";
import {GovernorUpgradeable} from "openzeppelin-upgradeable-v5/governance/GovernorUpgradeable.sol";
import {IERC20} from "openzeppelin-v5/token/ERC20/IERC20.sol";

struct Proposal {
    address[] targets;
    uint256[] values;
    bytes[] calldatas;
    string description;
    uint256 proposalId;
}

contract ProposalHelper is CreateL2ArbSysProposal, Test {
    function createL2ArbSysProposal(
        string memory _proposalDescription,
        address _oneOffUpgradeAddr,
        uint256 _minDelay,
        GovernorUpgradeable _governor,
        address _proposer
    ) public returns (Proposal memory) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            createL2ArbSysProposal(_proposalDescription, _oneOffUpgradeAddr, _minDelay);
        vm.prank(_proposer);
        uint256 _proposalId = _governor.propose(targets, values, calldatas, _proposalDescription);
        return Proposal(targets, values, calldatas, _proposalDescription, _proposalId);
    }

    function createTreasuryProposalForSingleTransfer(
        address _token,
        address _to,
        uint256 _amount,
        GovernorUpgradeable _governor,
        address _proposer
    ) public returns (Proposal memory) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = L2_ARB_TREASURY_FIXED_DELEGATE;
        bytes memory transferCalldata = abi.encodeWithSelector(
            IFixedDelegateErc20Wallet.transfer.selector, _token, _to, _amount
        );
        calldatas[0] = transferCalldata;
        string memory _proposalDescription = "treasury proposal";
        vm.prank(_proposer);
        uint256 _proposalId = _governor.propose(targets, values, calldatas, _proposalDescription);
        return Proposal(targets, values, calldatas, _proposalDescription, _proposalId);
    }

    function createMultiStepTreasuryProposal(
        address _token,
        address _to,
        uint256 _amount,
        GovernorUpgradeable _governor,
        address _proposer
    ) public returns (Proposal memory) {
        address[] memory targets = new address[](3);
        uint256[] memory values = new uint256[](3);
        bytes[] memory calldatas = new bytes[](3);

        targets[0] = L2_ARB_TREASURY_FIXED_DELEGATE;
        bytes memory transferCalldata = abi.encodeWithSelector(
            IFixedDelegateErc20Wallet.transfer.selector, _token, _to, _amount
        );
        calldatas[0] = transferCalldata;

        targets[1] = L2_ARB_TOKEN_ADDRESS;
        calldatas[1] = abi.encodeWithSelector(
            IERC20.approve.selector,
            0x3466EB008EDD8d5052446293D1a7D212cb65C646, /* Hedgey Finance: Batch Planner */
            42_500_000_000_000_000_000_000
        );

        targets[2] = 0x3466EB008EDD8d5052446293D1a7D212cb65C646; /* Hedgey Finance: Batch Planner */
        // https://arbiscan.io/tx/0x1149f00ccc422e9e36d3275593c463ac8c23f74cc730a434b8088aab913a56f9
        calldatas[2] =
            hex"94d37b5a0000000000000000000000001bb64af7fe05fc69c740609267d2abe3e119ef82000000000000000000000000912ce59144191c1204e64559fe8253a0e49e65480000000000000000000000000000000000000000000008ffedfb59597590000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000bfc1feca8b09a5c5d3effe7429ebe24b9c09ef580000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000000000000000010000000000000000000000002f6522bb4428da4588c7333efb4364a917b5bcca0000000000000000000000000000000000000000000008ffedfb5959759000000000000000000000000000000000000000000000000000000000000066322ec000000000000000000000000000000000000000000000000000000000665b0d40000000000000000000000000000000000000000000000000000b7dab267bcb33"; //From

        string memory _proposalDescription = "treasury proposal";
        vm.prank(_proposer);
        uint256 _proposalId = _governor.propose(targets, values, calldatas, _proposalDescription);
        return Proposal(targets, values, calldatas, _proposalDescription, _proposalId);
    }

    function createEthTransferTreasuryProposal(
        address _to,
        uint256 _amount,
        GovernorUpgradeable _governor,
        address _proposer
    ) public returns (Proposal memory) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = _to;
        values[0] = _amount;
        bytes memory transferCalldata = hex"";
        calldatas[0] = transferCalldata;
        string memory _proposalDescription = "treasury proposal";
        vm.prank(_proposer);
        uint256 _proposalId = _governor.propose(targets, values, calldatas, _proposalDescription);
        return Proposal(targets, values, calldatas, _proposalDescription, _proposalId);
    }
}
