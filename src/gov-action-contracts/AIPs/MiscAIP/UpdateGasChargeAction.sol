// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/precompiles/ArbOwner.sol";
import "@arbitrum/nitro-contracts/src/precompiles/ArbGasInfo.sol";

/// @notice Update fixed cost of posting a batch, which more accurately reflects actual cost.
/// Also properly disable amortized cost cap (should be 0, not max(int64))
contract UpdateGasChargeAction {
    int64 public immutable newPerBatchGasCharge;

    constructor(int64 _newPerBatchGasCharge) {
        newPerBatchGasCharge = _newPerBatchGasCharge;
    }

    function perform() external {
        ArbOwner arbOwner = ArbOwner(0x0000000000000000000000000000000000000070);
        arbOwner.setPerBatchGasCharge(newPerBatchGasCharge);
        arbOwner.setAmortizedCostCapBips(0);

        // verify
        ArbGasInfo arbGasInfo = ArbGasInfo(0x000000000000000000000000000000000000006C);
        require(
            arbGasInfo.getPerBatchGasCharge() == newPerBatchGasCharge,
            "UpdateGasChargeAction: PerBatchGasCharge set"
        );
        require(
            arbGasInfo.getAmortizedCostCapBips() == 0,
            "UpdateGasChargeAction: AmortizedCostCapBips set"
        );
    }
}
