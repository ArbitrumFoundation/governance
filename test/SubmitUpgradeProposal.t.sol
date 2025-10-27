// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import {Test} from "forge-std/Test.sol";
import {SubmitUpgradeProposalScript} from "scripts/forge-scripts/SubmitUpgradeProposalScript.s.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {
    MultiProxyUpgradeAction
} from "src/gov-action-contracts/gov-upgrade-contracts/upgrade-proxy/MultiProxyUpgradeAction.sol";
import {SetupNewGovernors} from "test/util/SetupNewGovernors.sol";
import {
    ProxyUpgradeAndCallAction
} from "src/gov-action-contracts/gov-upgrade-contracts/upgrade-proxy/ProxyUpgradeAndCallAction.sol";
import {L2ArbitrumGovernorV2} from "src/L2ArbitrumGovernorV2.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {L2ArbitrumGovernorV2Test} from "test/L2ArbitrumGovernorV2.t.sol";

contract SubmitUpgradeProposalTest is SetupNewGovernors, L2ArbitrumGovernorV2Test {
    event Upgraded(address indexed implementation);

    function setUp() public virtual override(SetupNewGovernors, L2ArbitrumGovernorV2Test) {
        SetupNewGovernors.setUp();
        _setMajorDelegates();
    }

    function test_SuccessfullyExecuteUpgradeProposal() public {
        MultiProxyUpgradeAction multiProxyUpgradeAction = new MultiProxyUpgradeAction(
            L2_PROXY_ADMIN_CONTRACT,
            L2_CORE_GOVERNOR,
            L2_TREASURY_GOVERNOR,
            address(newGovernorImplementation)
        );

        // Propose
        (
            address[] memory _targets,
            uint256[] memory _values,
            bytes[] memory _calldatas,
            string memory _description,
            uint256 _proposalId
        ) = submitUpgradeProposalScript.run(address(multiProxyUpgradeAction), L1_TIMELOCK_MIN_DELAY);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Pending)
        );
        vm.roll(block.number + currentCoreGovernor.votingDelay() + 1);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Active)
        );

        // Vote
        for (uint256 i; i < _majorDelegates.length; i++) {
            vm.prank(_majorDelegates[i]);
            currentCoreGovernor.castVote(_proposalId, uint8(VoteType.For));
        }

        // Success
        vm.roll(block.number + currentCoreGovernor.votingPeriod() + 1);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Succeeded)
        );

        // Queue
        currentCoreGovernor.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Queued)
        );
        vm.warp(block.timestamp + currentCoreTimelock.getMinDelay() + 1);

        vm.expectEmit();
        emit Upgraded(address(newGovernorImplementation));
        vm.expectEmit();
        emit Upgraded(address(newGovernorImplementation));

        // Execute
        currentCoreGovernor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));

        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Executed)
        );
        assertEq(
            ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
                .getProxyImplementation(
                    TransparentUpgradeableProxy(payable(address(currentCoreGovernor)))
                ),
            address(newGovernorImplementation)
        );
        assertEq(
            ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
                .getProxyImplementation(
                    TransparentUpgradeableProxy(payable(address(currentTreasuryGovernor)))
                ),
            address(newGovernorImplementation)
        );
        assertEq(
            ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
                .getProxyAdmin(TransparentUpgradeableProxy(payable(L2_CORE_GOVERNOR))),
            L2_PROXY_ADMIN_CONTRACT
        );
        assertEq(
            ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
                .getProxyAdmin(TransparentUpgradeableProxy(payable(L2_TREASURY_GOVERNOR))),
            L2_PROXY_ADMIN_CONTRACT
        );
    }

    function test_DefeatedExecuteUpgradeProposalDoesNotUpdateImplementation() public {
        address initialCoreGovernorImplementation = ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
            .getProxyImplementation(
                TransparentUpgradeableProxy(payable(address(currentCoreGovernor)))
            );

        address initialTreasuryGovernorImplementation = ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
            .getProxyImplementation(
                TransparentUpgradeableProxy(payable(address(currentTreasuryGovernor)))
            );

        MultiProxyUpgradeAction multiProxyUpgradeAction = new MultiProxyUpgradeAction(
            L2_PROXY_ADMIN_CONTRACT,
            L2_CORE_GOVERNOR,
            L2_TREASURY_GOVERNOR,
            address(newGovernorImplementation)
        );

        // Propose
        (
            ,/*address[] memory _targets*/ /*uint256[] memory _values*/ /*bytes[] memory _calldatas*/ /*string memory _description*/,,,
            uint256 _proposalId
        ) = submitUpgradeProposalScript.run(address(multiProxyUpgradeAction), L1_TIMELOCK_MIN_DELAY);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Pending)
        );
        vm.roll(block.number + currentCoreGovernor.votingDelay() + 1);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)), uint256(IGovernor.ProposalState.Active)
        );

        // Vote
        for (uint256 i; i < _majorDelegates.length; i++) {
            vm.prank(_majorDelegates[i]);
            currentCoreGovernor.castVote(_proposalId, uint8(VoteType.Against));
        }

        // Defeat
        vm.roll(block.number + currentCoreGovernor.votingPeriod() + 1);
        assertEq(
            uint256(currentCoreGovernor.state(_proposalId)),
            uint256(IGovernor.ProposalState.Defeated)
        );

        assertEq(
            ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
                .getProxyImplementation(
                    TransparentUpgradeableProxy(payable(address(currentCoreGovernor)))
                ),
            initialCoreGovernorImplementation
        );
        assertEq(
            ProxyAdmin(payable(L2_PROXY_ADMIN_CONTRACT))
                .getProxyImplementation(
                    TransparentUpgradeableProxy(payable(address(currentTreasuryGovernor)))
                ),
            initialTreasuryGovernorImplementation
        );
    }

    function testFuzz_RevertIf_ProxyAdminOwnerMismatch(address _wrongOwner) public {
        vm.assume(_wrongOwner != L2_UPGRADE_EXECUTOR);
        vm.assume(_wrongOwner != address(0));

        MultiProxyUpgradeAction multiProxyUpgradeAction = new MultiProxyUpgradeAction(
            L2_PROXY_ADMIN_CONTRACT,
            L2_CORE_GOVERNOR,
            L2_TREASURY_GOVERNOR,
            address(newGovernorImplementation)
        );

        vm.prank(L2_UPGRADE_EXECUTOR);
        ProxyAdmin(L2_PROXY_ADMIN_CONTRACT).transferOwnership(_wrongOwner);

        vm.expectRevert("ProxyAdmin owner mismatch");
        submitUpgradeProposalScript.run(address(multiProxyUpgradeAction), L1_TIMELOCK_MIN_DELAY);
    }

    function testFuzz_RevertIf_CoreGovernorProxyAdminMismatch(address _wrongProxyAdmin) public {
        vm.assume(_wrongProxyAdmin != L2_PROXY_ADMIN_CONTRACT);
        vm.assume(_wrongProxyAdmin != address(0));

        address[] memory targets = new address[](1);
        targets[0] = L2_ARB_SYS;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.mockCall(
            L2_PROXY_ADMIN_CONTRACT,
            abi.encodeWithSelector(
                ProxyAdmin.getProxyAdmin.selector,
                TransparentUpgradeableProxy(payable(L2_CORE_GOVERNOR))
            ),
            abi.encode(_wrongProxyAdmin)
        );

        vm.expectRevert("Core Governor proxy admin mismatch");
        submitUpgradeProposalScript.checkConfigurationAndPayload(targets, values, calldatas);
    }

    function testFuzz_RevertIf_TreasuryGovernorProxyAdminMismatch(address _wrongProxyAdmin) public {
        vm.assume(_wrongProxyAdmin != L2_PROXY_ADMIN_CONTRACT);
        vm.assume(_wrongProxyAdmin != address(0));

        address[] memory targets = new address[](1);
        targets[0] = L2_ARB_SYS;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.mockCall(
            L2_PROXY_ADMIN_CONTRACT,
            abi.encodeWithSelector(
                ProxyAdmin.getProxyAdmin.selector,
                TransparentUpgradeableProxy(payable(L2_TREASURY_GOVERNOR))
            ),
            abi.encode(_wrongProxyAdmin)
        );

        vm.expectRevert("Treasury Governor proxy admin mismatch");
        submitUpgradeProposalScript.checkConfigurationAndPayload(targets, values, calldatas);
    }

    function test_RevertIf_MultipleTargets() public {
        address[] memory targets = new address[](2);
        targets[0] = L2_ARB_SYS;
        targets[1] = L2_ARB_SYS;
        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;
        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = "";
        calldatas[1] = "";

        vm.expectRevert("Invalid proposal arrays");
        submitUpgradeProposalScript.checkConfigurationAndPayload(targets, values, calldatas);
    }

    function testFuzz_RevertIf_WrongTarget(address _wrongTarget) public {
        vm.assume(_wrongTarget != L2_ARB_SYS);
        vm.assume(_wrongTarget != address(0));

        address[] memory targets = new address[](1);
        targets[0] = _wrongTarget;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.expectRevert("Invalid proposal arrays");
        submitUpgradeProposalScript.checkConfigurationAndPayload(targets, values, calldatas);
    }

    function testFuzz_RevertIf_NonZeroValue(uint256 _wrongValue) public {
        vm.assume(_wrongValue != 0);

        address[] memory targets = new address[](1);
        targets[0] = L2_ARB_SYS;
        uint256[] memory values = new uint256[](1);
        values[0] = _wrongValue;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.expectRevert("Invalid proposal arrays");
        submitUpgradeProposalScript.checkConfigurationAndPayload(targets, values, calldatas);
    }

    function test_RevertIf_MultipleCalldatas() public {
        address[] memory targets = new address[](1);
        targets[0] = L2_ARB_SYS;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = "";
        calldatas[1] = "";

        vm.expectRevert("Invalid proposal arrays");
        submitUpgradeProposalScript.checkConfigurationAndPayload(targets, values, calldatas);
    }
}

interface IUpgradeExecutor {
    function execute(address to, bytes calldata data) external payable;
}
