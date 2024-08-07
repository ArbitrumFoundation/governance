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

        // Upgrade rollup logics
        DoubleLogicUUPSUpgradeable(rollupAddress).upgradeTo(newPrimaryLogic);
        DoubleLogicUUPSUpgradeable(rollupAddress).upgradeSecondaryTo(newSecondaryLogic);

        // Setup AnyTrustFastConfirmer
        require(
            IRollupAdminFC(rollupAddress).anyTrustFastConfirmer() == address(0),
            "UpgradeAndEnableFastConfirmAction: Fast confirm already enabled"
        );
        IRollupAdminFC(rollupAddress).setAnyTrustFastConfirmer(
            anyTrustFastConfirmer
        );
        require(
            IRollupAdminFC(rollupAddress).anyTrustFastConfirmer()
                == anyTrustFastConfirmer,
            "UpgradeAndEnableFastConfirmAction: Unexpected anyTrustFastConfirmer"
        );

        // Set AnyTrustFastConfirmer as validator
        address[] memory validators = new address[](1);
        validators[0] = anyTrustFastConfirmer;
        bool[] memory values = new bool[](1);
        values[0] = true;
        IRollupAdmin(rollupAddress).setValidator(validators, values);
        require(
            IRollupCore(rollupAddress).isValidator(anyTrustFastConfirmer),
            "UpgradeAndEnableFastConfirmAction: Failed to set validator"
        );

        // Set minimum assertion period
        IRollupAdmin(rollupAddress).setMinimumAssertionPeriod(
            newMinimumAssertionPeriod
        );
        require(
            IRollupCore(rollupAddress).minimumAssertionPeriod()
                == newMinimumAssertionPeriod,
            "UpgradeAndEnableFastConfirmAction: Failed to set minimum assertion period"
        );
    }
}
