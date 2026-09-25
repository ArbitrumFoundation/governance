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
        SetGlamsterdamGasParamsAction action = new SetGlamsterdamGasParamsAction();
        assertEq(action.newParentGasFloorPerToken(), 16, "floor");
        assertEq(action.newPerBatchGasCharge(), 530_000, "per batch");
        action.perform();

        assertEq(
            IArbOwnerPublicGlamsterdam(ARB_OWNER_PUBLIC).getParentGasFloorPerToken(),
            16,
            "parentGasFloorPerToken"
        );
        assertEq(
            IArbGasInfoGlamsterdam(ARB_GAS_INFO).getPerBatchGasCharge(),
            530_000,
            "perBatchGasCharge"
        );
    }

    /// @notice The post-state assertions have to actually fire. Etch an ArbOwner whose setters do
    ///         nothing and check perform() refuses to report success.
    function test_revertsIfFloorDoesNotTakeEffect() public {
        vm.etch(ARB_OWNER, address(new ArbOwnerMockThatIgnoresWrites()).code);
        SetGlamsterdamGasParamsAction action = new SetGlamsterdamGasParamsAction();

        vm.expectRevert("SetGlamsterdamGasParamsAction: parent gas floor per token");
        action.perform();
    }

    function test_revertsIfPerBatchChargeDoesNotTakeEffect() public {
        // Set the expected floor before disabling writes to isolate the per-batch assertion.
        ArbOwnerMock(ARB_OWNER).setParentGasFloorPerToken(16);
        vm.etch(ARB_OWNER, address(new ArbOwnerMockThatIgnoresWrites()).code);
        SetGlamsterdamGasParamsAction action = new SetGlamsterdamGasParamsAction();

        vm.expectRevert("SetGlamsterdamGasParamsAction: per batch gas charge");
        action.perform();
    }

    /// @notice The action is delegatecalled by the L2 UpgradeExecutor, so it must hold no storage
    ///         and read its parameters out of its own bytecode.
    function test_worksUnderDelegatecall() public {
        SetGlamsterdamGasParamsAction action = new SetGlamsterdamGasParamsAction();
        GasParamsDelegateCaller caller = new GasParamsDelegateCaller();
        caller.performVia(address(action));

        assertEq(
            IArbOwnerPublicGlamsterdam(ARB_OWNER_PUBLIC).getParentGasFloorPerToken(), 16, "floor"
        );
        assertEq(IArbGasInfoGlamsterdam(ARB_GAS_INFO).getPerBatchGasCharge(), 530_000, "per batch");
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
