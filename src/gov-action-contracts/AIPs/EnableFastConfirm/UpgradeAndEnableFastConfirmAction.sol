// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/libraries/DoubleLogicUUPSUpgradeable.sol";

import "../../address-registries/interfaces.sol";

interface IRollupAdminFC {
    function anyTrustFastConfirmer() external view returns (address);
    function setAnyTrustFastConfirmer(address _anyTrustFastConfirmer) external;
}

/// @notice Upgrades the rollup logic to v2.1 and enables fast confirmation
contract UpgradeAndEnableFastConfirmAction {
    IRollupGetter public immutable addressRegistry;
    address public immutable newPrimaryLogic;
    address public immutable newSecondaryLogic;
    address public immutable anyTrustFastConfirmer;
    uint256 public immutable newMinimumAssertionPeriod;

    constructor(
        IRollupGetter _addressRegistry,
        address _newPrimaryLogic,
        address _newSecondaryLogic,
        address _anyTrustFastConfirmer,
        uint256 _newMinimumAssertionPeriod
    ) {
        addressRegistry = _addressRegistry;
        newPrimaryLogic = _newPrimaryLogic;
        newSecondaryLogic = _newSecondaryLogic;
        anyTrustFastConfirmer = _anyTrustFastConfirmer;
        newMinimumAssertionPeriod = _newMinimumAssertionPeriod;
    }

    function perform() external {
        address rollupAddress = address(addressRegistry.rollup());

        DoubleLogicUUPSUpgradeable(rollupAddress).upgradeTo(newPrimaryLogic);
        DoubleLogicUUPSUpgradeable(rollupAddress).upgradeSecondaryTo(newSecondaryLogic);

        // Setup AnyTrustFastConfirmer
        require(
            IRollupAdminFC(address(addressRegistry.rollup())).anyTrustFastConfirmer() == address(0),
            "UpgradeAndEnableFastConfirmAction: Fast confirm already enabled"
        );
        IRollupAdminFC(address(addressRegistry.rollup())).setAnyTrustFastConfirmer(
            anyTrustFastConfirmer
        );
        require(
            IRollupAdminFC(address(addressRegistry.rollup())).anyTrustFastConfirmer()
                == anyTrustFastConfirmer,
            "UpgradeAndEnableFastConfirmAction: Unexpected anyTrustFastConfirmer"
        );

        // Set AnyTrustFastConfirmer as validator
        address[] memory validators = new address[](1);
        validators[0] = anyTrustFastConfirmer;
        bool[] memory values = new bool[](1);
        values[0] = true;
        IRollupAdmin(address(addressRegistry.rollup())).setValidator(validators, values);
        require(
            IRollupCore(address(addressRegistry.rollup())).isValidator(anyTrustFastConfirmer),
            "UpgradeAndEnableFastConfirmAction: Failed to set validator"
        );

        // Set minimum assertion period
        IRollupAdmin(address(addressRegistry.rollup())).setMinimumAssertionPeriod(
            newMinimumAssertionPeriod
        );
        require(
            IRollupCore(address(addressRegistry.rollup())).minimumAssertionPeriod()
                == newMinimumAssertionPeriod,
            "UpgradeAndEnableFastConfirmAction: Failed to set minimum assertion period"
        );
    }
}
