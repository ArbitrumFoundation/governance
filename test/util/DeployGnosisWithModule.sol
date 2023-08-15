// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import "@gnosis.pm/safe-contracts/contracts/base/ModuleManager.sol";

import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "forge-std/Test.sol";

contract GnosisModuleEnabler is GnosisSafeL2 {
    function enableModuleUnguarded(address module) public {
        // Module address cannot be null or sentinel.
        require(module != address(0) && module != SENTINEL_MODULES, "GS101");
        // Module cannot be added twice.
        require(modules[module] == address(0), "GS102");
        modules[module] = modules[SENTINEL_MODULES];
        modules[SENTINEL_MODULES] = module;
        emit EnabledModule(module);
    }
}

contract DeployGnosisWithModule is Test {
    function deploySafe(address[] memory _owners, uint256 _threshold, address _module)
        public
        returns (address safeAddress)
    {
        GnosisSafeL2 safeLogic = new GnosisSafeL2();
        GnosisModuleEnabler moduleEnabler = new GnosisModuleEnabler();

        GnosisSafeProxyFactory safeProxyFactory = new GnosisSafeProxyFactory();

        GnosisSafeProxy safeProxy = safeProxyFactory.createProxy(address(safeLogic), "0x");
        GnosisSafeL2 safe = GnosisSafeL2(payable(address(safeProxy)));
        if (_module != address(0)) {
            safe.setup(
                _owners,
                _threshold,
                address(moduleEnabler),
                abi.encodeWithSelector(GnosisModuleEnabler.enableModuleUnguarded.selector, _module),
                address(0),
                address(0),
                0,
                payable(address(0))
            );
        } else {
            safe.setup(
                _owners,
                _threshold,
                address(0),
                "0x",
                address(0),
                address(0),
                0,
                payable(address(0))
            );
        }

        assertTrue(safe.isModuleEnabled(_module), "MODULE_ERROR");

        return address(safe);
    }
}
