// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

// ArbOwner.setParentGasFloorPerToken is available from ArbOS 50 and is not present in the ArbOwner
// interface shipped with the pinned nitro-contracts 3.1.1, so the methods this action needs are
// declared locally rather than bumping the dependency. Same approach as ArbOneSetAtlasFeesAction,
// which declares its own IArbGasInfo.
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
///            EIP-8037, which prices new state at 1530 gas per byte. Each batch creates two new
///            storage slots, sequencerInboxAccs.push in the bridge and delayedInboxAccs.push from
///            the batch spending report, at 64 bytes each (key hash plus value). That is
///            2 * 64 * 1530 = 195,840 gas per batch that the pricer does not currently account for.
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

    uint64 public immutable newParentGasFloorPerToken;
    int64 public immutable newPerBatchGasCharge;

    constructor(uint64 _newParentGasFloorPerToken, int64 _newPerBatchGasCharge) {
        newParentGasFloorPerToken = _newParentGasFloorPerToken;
        newPerBatchGasCharge = _newPerBatchGasCharge;
    }

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

/// @notice Glamsterdam parent chain pricing parameters for Arbitrum One.
contract ArbOneSetGlamsterdamGasParamsAction is SetGlamsterdamGasParamsAction {
    constructor()
        SetGlamsterdamGasParamsAction(
            // parentGasFloorPerToken, currently 10. EIP-7976 sets TOTAL_COST_FLOOR_PER_TOKEN to 16.
            //
            // Note this will not bind in practice while Arbitrum One posts blob batches only: the
            // floor branch in ArbOS computes roughly 16 * 172 + 21000 = 23,752 gas for a blob batch,
            // against a gasSpent already well above 250,000 from perBatchGasCharge alone. It is set
            // anyway so the chain mirrors the parent chain rule, and so the value is right if a
            // small calldata batch is ever posted.
            16,
            // perBatchGasCharge, currently 210,000.
            //
            // TODO: validate this charge against the final EIP-8037 text and measure batch posting
            // costs on a devnet before this goes to a vote. Too low and the
            // pricer under-recovers batch posting costs, too high and users overpay.
            530_000
        )
    {}
}

/// @notice Glamsterdam parent chain pricing parameters for Nova.
/// @dev    Nova currently runs the same values as Arbitrum One (ArbOS 61, perBatchGasCharge
///         210,000, parentGasFloorPerToken 10) and posts blob batches in the same shape, so it takes
///         the same new values. Re-check before deploying in case the chains diverge.
contract NovaSetGlamsterdamGasParamsAction is SetGlamsterdamGasParamsAction {
    constructor()
        SetGlamsterdamGasParamsAction(
            16,
            // TODO: see ArbOneSetGlamsterdamGasParamsAction. Confirm that Nova's batch shape
            // justifies the same charge.
            530_000
        )
    {}
}
