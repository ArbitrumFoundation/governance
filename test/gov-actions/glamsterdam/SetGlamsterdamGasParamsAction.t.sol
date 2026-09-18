// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../../../src/gov-action-contracts/glamsterdam/SetGlamsterdamGasParamsAction.sol";
import "../../util/MockArbOwner.sol";

contract SetGlamsterdamGasParamsActionTest is Test {
    address constant ARB_OWNER_PUBLIC = 0x000000000000000000000000000000000000006b;
    address constant ARB_GAS_INFO = 0x000000000000000000000000000000000000006C;

    /// @notice Values live on Arbitrum One and Nova at the time of writing.
    uint64 constant CURRENT_PARENT_GAS_FLOOR_PER_TOKEN = 10;
    int64 constant CURRENT_PER_BATCH_GAS_CHARGE = 210_000;

    function setUp() public {
        vm.etch(ARB_OWNER, address(new ArbOwnerMock()).code);
        vm.etch(ARB_OWNER_PUBLIC, address(new ArbOwnerPublicMock()).code);
        vm.etch(ARB_GAS_INFO, address(new ArbGasInfoMock()).code);

        ArbOwnerMock(ARB_OWNER).setParentGasFloorPerToken(CURRENT_PARENT_GAS_FLOOR_PER_TOKEN);
        ArbOwnerMock(ARB_OWNER).setPerBatchGasCharge(CURRENT_PER_BATCH_GAS_CHARGE);
    }

    function test_setsBothValues() public {
        SetGlamsterdamGasParamsAction action = new SetGlamsterdamGasParamsAction(16, 400_000);
        action.perform();

        assertEq(
            IArbOwnerPublicGlamsterdam(ARB_OWNER_PUBLIC).getParentGasFloorPerToken(),
            16,
            "parentGasFloorPerToken"
        );
        assertEq(
            IArbGasInfoGlamsterdam(ARB_GAS_INFO).getPerBatchGasCharge(),
            400_000,
            "perBatchGasCharge"
        );
    }

    function test_arbOneChildUsesExpectedValues() public {
        ArbOneSetGlamsterdamGasParamsAction action = new ArbOneSetGlamsterdamGasParamsAction();
        assertEq(action.newParentGasFloorPerToken(), 16, "arb one floor");
        assertEq(action.newPerBatchGasCharge(), 400_000, "arb one per batch");

        action.perform();
        assertEq(
            IArbOwnerPublicGlamsterdam(ARB_OWNER_PUBLIC).getParentGasFloorPerToken(), 16, "floor"
        );
        assertEq(IArbGasInfoGlamsterdam(ARB_GAS_INFO).getPerBatchGasCharge(), 400_000, "per batch");
    }

    function test_novaChildUsesExpectedValues() public {
        NovaSetGlamsterdamGasParamsAction action = new NovaSetGlamsterdamGasParamsAction();
        assertEq(action.newParentGasFloorPerToken(), 16, "nova floor");
        assertEq(action.newPerBatchGasCharge(), 400_000, "nova per batch");

        action.perform();
        assertEq(
            IArbOwnerPublicGlamsterdam(ARB_OWNER_PUBLIC).getParentGasFloorPerToken(), 16, "floor"
        );
        assertEq(IArbGasInfoGlamsterdam(ARB_GAS_INFO).getPerBatchGasCharge(), 400_000, "per batch");
    }

    /// @notice Running twice must be a no-op rather than a revert. A batch that reverts on the fork
    ///         gate is re-executed later, so perform() can be reached more than once.
    function test_isIdempotent() public {
        SetGlamsterdamGasParamsAction action = new SetGlamsterdamGasParamsAction(16, 400_000);
        action.perform();
        action.perform();

        assertEq(
            IArbOwnerPublicGlamsterdam(ARB_OWNER_PUBLIC).getParentGasFloorPerToken(), 16, "floor"
        );
        assertEq(IArbGasInfoGlamsterdam(ARB_GAS_INFO).getPerBatchGasCharge(), 400_000, "per batch");
    }

    /// @notice The post-state assertions have to actually fire. Etch an ArbOwner whose setters do
    ///         nothing and check perform() refuses to report success.
    function test_revertsIfFloorDoesNotTakeEffect() public {
        vm.etch(ARB_OWNER, address(new ArbOwnerMockThatIgnoresWrites()).code);
        SetGlamsterdamGasParamsAction action = new SetGlamsterdamGasParamsAction(16, 400_000);

        vm.expectRevert("SetGlamsterdamGasParamsAction: parent gas floor per token");
        action.perform();
    }

    function test_revertsIfPerBatchChargeDoesNotTakeEffect() public {
        // vm.etch replaces code but not storage, so the values written in setUp survive. Target the
        // floor that is already stored, so the floor assertion passes and the per batch assertion is
        // the one that fires.
        vm.etch(ARB_OWNER, address(new ArbOwnerMockThatIgnoresWrites()).code);
        SetGlamsterdamGasParamsAction action =
            new SetGlamsterdamGasParamsAction(CURRENT_PARENT_GAS_FLOOR_PER_TOKEN, 400_000);

        vm.expectRevert("SetGlamsterdamGasParamsAction: per batch gas charge");
        action.perform();
    }

    /// @notice The action is delegatecalled by the L2 UpgradeExecutor, so it must hold no storage
    ///         and read its parameters out of its own bytecode.
    function test_worksUnderDelegatecall() public {
        ArbOneSetGlamsterdamGasParamsAction action = new ArbOneSetGlamsterdamGasParamsAction();
        GasParamsDelegateCaller caller = new GasParamsDelegateCaller();
        caller.performVia(address(action));

        assertEq(
            IArbOwnerPublicGlamsterdam(ARB_OWNER_PUBLIC).getParentGasFloorPerToken(), 16, "floor"
        );
        assertEq(IArbGasInfoGlamsterdam(ARB_GAS_INFO).getPerBatchGasCharge(), 400_000, "per batch");
    }
}

contract GasParamsDelegateCaller {
    function performVia(address action) external {
        (bool success, bytes memory returnData) =
            action.delegatecall(abi.encodeWithSignature("perform()"));
        if (!success) {
            assembly {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }
}
