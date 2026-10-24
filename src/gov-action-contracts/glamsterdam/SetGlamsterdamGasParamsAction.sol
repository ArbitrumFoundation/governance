// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

interface IArbOwnerGlamsterdam {
    /// @notice Set how much the parent chain charges per calldata token. Mirrors
    ///         TOTAL_COST_FLOOR_PER_TOKEN from EIP-7623 / EIP-7976. ArbOS 50+.
    function setParentGasFloorPerToken(uint64 floorPerToken) external;
    /// @notice Set the base charge, in parent chain gas, attributed to each batch by the pricer.
    function setPerBatchGasCharge(int64 cost) external;
}

interface IArbOwnerPublicGlamsterdam {
    function getParentGasFloorPerToken() external view returns (uint64);
}

interface IArbGasInfoGlamsterdam {
    function getPerBatchGasCharge() external view returns (int64);
}

/// @notice Updates the parent chain pricing parameters of an Arbitrum chain for the Glamsterdam
///         fork on Ethereum.
///
///         Two changes, both on the ArbOwner precompile:
///
///         1. parentGasFloorPerToken 10 -> 16, mirroring EIP-7976, which raises
///            TOTAL_COST_FLOOR_PER_TOKEN to 16 (a uniform 64 gas per calldata byte).
///
///         2. perBatchGasCharge, covering the increase in what a batch actually costs to post under
///            EIP-8037.
///
/// @dev    This action must not execute before the fork is live on Ethereum: until then these
///         values describe parent chain rules that do not yet apply. Pair it with
///         GlamsterdamForkGateAction as a host chain action in the same proposal, which reverts the
///         whole L1 timelock batch, retryable ticket creation included, until the fork has landed.
contract SetGlamsterdamGasParamsAction {
    IArbOwnerGlamsterdam public constant arbOwner =
        IArbOwnerGlamsterdam(0x0000000000000000000000000000000000000070);
    IArbOwnerPublicGlamsterdam public constant arbOwnerPublic =
        IArbOwnerPublicGlamsterdam(0x000000000000000000000000000000000000006b);
    IArbGasInfoGlamsterdam public constant arbGasInfo =
        IArbGasInfoGlamsterdam(0x000000000000000000000000000000000000006C);

    // Store EIP-7976's floor coefficient (16 gas per token) for potential use by a future
    // Nitro pricing algorithm. Arb1 will not post calldata batches after Glamsterdam.
    uint64 public constant newParentGasFloorPerToken = 16;

    /// @dev Currently 210,000. Assumes blob batches, no gas refunder, and unchanged L1 pricing.
    ///      Measured batch gas rises from ~171k today (Arb1, with a gas refunder) to ~353k after
    ///      Glamsterdam without one (2.07x) [1]. Scale the existing margin (210k + 42k - 171k)
    ///      proportionally to preserve the break-even base-fee/tip ratio, then subtract the ~42k
    ///      from LegacyCostForStats [2]: 353k + (81k * 2.07) - 42k ≈ 479k, rounded to 480k.
    ///
    ///      [1] https://effective-spork-5wwmq3e.pages.github.io/harness/viewer.html
    ///      [2] https://github.com/OffchainLabs/nitro/blob/0e18b1f3696c201c0d40396cf6d258916e0a647a/arbos/arbostypes/incomingmessage.go#L182-L189
    int64 public constant newPerBatchGasCharge = 480_000;

    function perform() external {
        arbOwner.setParentGasFloorPerToken(newParentGasFloorPerToken);
        arbOwner.setPerBatchGasCharge(newPerBatchGasCharge);

        require(
            arbOwnerPublic.getParentGasFloorPerToken() == newParentGasFloorPerToken,
            "SetGlamsterdamGasParamsAction: parent gas floor per token"
        );
        require(
            arbGasInfo.getPerBatchGasCharge() == newPerBatchGasCharge,
            "SetGlamsterdamGasParamsAction: per batch gas charge"
        );
    }
}
