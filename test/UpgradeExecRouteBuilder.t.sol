// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/UpgradeExecRouteBuilder.sol";
import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";

import "forge-std/Test.sol";

contract UpgradeExecRouteBuilderTest is Test {
    address l1TimelockAddress = 0xE6841D92B0C345144506576eC13ECf5103aC7f49;
    address arbSys = 0x0000000000000000000000000000000000000064;
    // generated using the an altered proposal creator that calls scheduleBatch instead of schedule
    bytes aipData =
        hex"8f2a0bb000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000000067565fcc91c79be6e957056bdf0ed93287216afcc5ea02fec16f1900a177a3c5000000000000000000000000000000000000000000000000000000000003f4800000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a723c008e76e379c55599d2e4d93879beafda79c000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001800000000000000000000000004dbd4fc535ac27206064b68ffcf827b0a60bab3f000000000000000000000000cf57572261c7c2bcf21ffd220ea7d1a27d40a82700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000841cff79cd0000000000000000000000006274106eedd4848371d2c09e0352d67b795ed51600000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000004b147f40c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    // same as aipData but execute selector replaced with executeCall
    bytes aipDataExecuteCall = 
        hex"8f2a0bb000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000000067565fcc91c79be6e957056bdf0ed93287216afcc5ea02fec16f1900a177a3c5000000000000000000000000000000000000000000000000000000000003f4800000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a723c008e76e379c55599d2e4d93879beafda79c000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001800000000000000000000000004dbd4fc535ac27206064b68ffcf827b0a60bab3f000000000000000000000000cf57572261c7c2bcf21ffd220ea7d1a27d40a82700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000084bca8c7b50000000000000000000000006274106eedd4848371d2c09e0352d67b795ed51600000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000004b147f40c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    address aip1Point2ActionAddress = 0x6274106eedD4848371D2C09e0352d67B795ED516;
    bytes32 aip1Point2TimelockSalt =
        0x67565fcc91c79be6e957056bdf0ed93287216afcc5ea02fec16f1900a177a3c5;

    function deployRouteBuilder() internal returns (UpgradeExecRouteBuilder) {
        ChainAndUpExecLocation[] memory chainLocations = new ChainAndUpExecLocation[](1);
        chainLocations[0] = ChainAndUpExecLocation({
            chainId: 42_161,
            location: UpExecLocation({
                upgradeExecutor: 0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827,
                inbox: 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f
            })
        });

        return new UpgradeExecRouteBuilder(chainLocations, l1TimelockAddress, 259_200);
    }

    // test that aip1.2 would have been created with the same call data if it had used
    // the route builder
    function testAIP1Point2() public {
        UpgradeExecRouteBuilder routeBuilder = deployRouteBuilder();

        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 42_161;
        address[] memory actionAddresses = new address[](1);
        actionAddresses[0] = aip1Point2ActionAddress;
        (address to, bytes memory data) = routeBuilder.createActionRouteDataWithDefaults(
            chainIds, actionAddresses, aip1Point2TimelockSalt
        );

        assertEq(to, arbSys);
        assertEq(
            data, abi.encodeWithSelector(ArbSys.sendTxToL1.selector, l1TimelockAddress, aipData)
        );
    }

    function testActionType() public {
        UpgradeExecRouteBuilder routeBuilder = deployRouteBuilder();

        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 42_161;
        address[] memory actionAddresses = new address[](1);
        actionAddresses[0] = aip1Point2ActionAddress;
        uint256[] memory actionValues = new uint256[](1);
        actionValues[0] = 0;
        bytes[] memory actionDatas = new bytes[](1);
        actionDatas[0] = abi.encodeWithSignature("perform()");
        bytes32 predecessor = 0;
        bytes32 salt = aip1Point2TimelockSalt;

        uint256[] memory actionTypes = new uint256[](1);

        // execute
        (address to, bytes memory data) = routeBuilder.createActionRouteData2(
            chainIds, actionAddresses, actionValues, actionDatas, actionTypes, predecessor, salt
        );
        assertEq(to, arbSys);
        assertEq(
            data, abi.encodeWithSelector(ArbSys.sendTxToL1.selector, l1TimelockAddress, aipData)
        );

        // executeCall
        actionTypes[0] = 1;
        (address to2, bytes memory data2) = routeBuilder.createActionRouteData2(
            chainIds, actionAddresses, actionValues, actionDatas, actionTypes, predecessor, salt
        );
        assertEq(to2, arbSys);
        assertEq(
            data2, abi.encodeWithSelector(ArbSys.sendTxToL1.selector, l1TimelockAddress, aipDataExecuteCall)
        );
    }

    // test all the error conditions for the createActionRouteData funtion on the route builder
    function testRouteBuilderErrors() public {
        UpgradeExecRouteBuilder routeBuilder = deployRouteBuilder();
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 42_161;
        address[] memory actionAddresses = new address[](1);
        actionAddresses[0] = aip1Point2ActionAddress;
        uint256[] memory actionValues = new uint256[](1);
        actionValues[0] = 2;
        bytes[] memory actionDatas = new bytes[](1);
        actionDatas[0] = aipData;
        bytes32 predecessor = bytes32(uint256(1));
        bytes32 salt = bytes32(uint256(0x20));
        vm.expectRevert(
            abi.encodeWithSelector(UpgradeExecRouteBuilder.ParamLengthMismatch.selector, 1, 0)
        );
        routeBuilder.createActionRouteData(
            chainIds, new address[](0), actionValues, actionDatas, predecessor, salt
        );

        vm.expectRevert(
            abi.encodeWithSelector(UpgradeExecRouteBuilder.ParamLengthMismatch.selector, 1, 0)
        );
        routeBuilder.createActionRouteData(
            chainIds, actionAddresses, new uint256[](0), actionDatas, predecessor, salt
        );

        vm.expectRevert(
            abi.encodeWithSelector(UpgradeExecRouteBuilder.ParamLengthMismatch.selector, 1, 0)
        );
        routeBuilder.createActionRouteData(
            chainIds, actionAddresses, actionValues, new bytes[](0), predecessor, salt
        );

        vm.expectRevert(
            abi.encodeWithSelector(UpgradeExecRouteBuilder.ParamLengthMismatch.selector, 1, 0)
        );
        routeBuilder.createActionRouteData2(
            chainIds, actionAddresses, actionValues, actionDatas, new uint256[](0), predecessor, salt
        );

        uint256[] memory badChainIds = new uint256[](1);
        badChainIds[0] = 42_162;
        vm.expectRevert(
            abi.encodeWithSelector(UpgradeExecRouteBuilder.UpgadeExecDoesntExist.selector, 42_162)
        );
        routeBuilder.createActionRouteData(
            badChainIds, actionAddresses, actionValues, actionDatas, predecessor, salt
        );

        bytes[] memory badActionDatas = new bytes[](1);
        badActionDatas[0] = new bytes(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                UpgradeExecRouteBuilder.EmptyActionBytesData.selector, badActionDatas
            )
        );
        routeBuilder.createActionRouteData(
            chainIds, actionAddresses, actionValues, badActionDatas, predecessor, salt
        );

        uint256[] memory badActionTypes = new uint256[](1);
        badActionTypes[0] = 2;
        vm.expectRevert(
            abi.encodeWithSelector(UpgradeExecRouteBuilder.InvalidActionType.selector, 2)
        );
        routeBuilder.createActionRouteData2(
            chainIds, actionAddresses, actionValues, actionDatas, badActionTypes, predecessor, salt
        );
    }
}
