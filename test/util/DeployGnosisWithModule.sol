// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "forge-std/Test.sol";

contract DeployGnosisWithModule is Test {
    function deploySafe(address[] memory _owners, uint256 _threshold, address _module)
        public
        returns (address safeAddress)
    {
        GnosisSafeL2 safeLogic = new GnosisSafeL2();
        GnosisSafeProxyFactory safeProxyFactory = new GnosisSafeProxyFactory();

        GnosisSafeProxy safeProxy = safeProxyFactory.createProxy(address(safeLogic), "0x");
        GnosisSafeL2 safe = GnosisSafeL2(payable(address(safeProxy)));
        safe.setup(
            _owners, _threshold, address(0), "0x", address(0), address(0), 0, payable(address(0))
        );
        if (_module != address(0)) {
            vm.prank(address(safe));
            safe.enableModule(_module);
        }
        return address(safe);
    }
}
