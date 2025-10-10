// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

// Governor deployment constants that are shared between the Core Governor and the
// Treasury Governor. These should be carefully checked and reviewed before final deployment.
contract DeployConstants {
    address public constant L2_ARB_TOKEN_ADDRESS = 0x912CE59144191C1204E64559FE8253a0e49E6548;

    address public constant L2_CORE_GOVERNOR = 0xf07DeD9dC292157749B6Fd268E37DF6EA38395B9;
    address public constant L2_CORE_GOVERNOR_TIMELOCK = 0x34d45e99f7D8c45ed05B5cA72D54bbD1fb3F98f0;
    address public constant L2_TREASURY_GOVERNOR = 0x789fC99093B09aD01C34DC7251D0C89ce743e5a4;
    address public constant L2_TREASURY_GOVERNOR_TIMELOCK =
        0xbFc1FECa8B09A5c5D3EFfE7429eBE24b9c09EF58;
    address public constant L2_PROXY_ADMIN_OWNER = L2_UPGRADE_EXECUTOR;
    address public constant L2_PROXY_ADMIN_CONTRACT = 0xdb216562328215E010F819B5aBe947bad4ca961e;

    address public constant L2_ARB_SYS = 0x0000000000000000000000000000000000000064;
    address public constant L2_ARB_RETRYABLE_TX = 0x000000000000000000000000000000000000006E;
    address public constant L2_SECURITY_COUNCIL_9 = 0x423552c0F05baCCac5Bfa91C6dCF1dc53a0A1641;

    address public constant L1_TIMELOCK = 0xE6841D92B0C345144506576eC13ECf5103aC7f49;
    uint256 public constant L1_TIMELOCK_MIN_DELAY = 259_200;
    address public constant L1_ARB_ONE_DELAYED_INBOX = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f;

    // ===========================================================================================
    // TODO: Update these values after the deployment process
    // ===========================================================================================
    address public constant L2_ARBITRUM_GOVERNOR_V2_IMPLEMENTATION = address(0); // TODO: Update after the core governor is deployed.
    bool public constant UPGRADE_PROPOSAL_PASSED_ONCHAIN = false; // TODO: Update after the upgrade proposal is passed.
    // ===========================================================================================

    address public constant L2_UPGRADE_EXECUTOR = 0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827;
    address public constant L2_RETRYABLE_TICKET_MAGIC = 0xa723C008e76E379c55599D2E4d93879BeaFDa79C;
}
