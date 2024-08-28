// SPDX-License-Identifier: AGPL-3.0-only
// slither-disable-start reentrancy-benign

pragma solidity 0.8.26;

// Inheritable extension holding governor deployment constants that are shared between the Core Governor and the
// Treasury Governor. These should be carefully checked and reviewed before final deployment.
contract SharedGovernorConstants {
    uint256 constant FORK_BLOCK = 245_608_716; // Arbitrary recent block
    address public constant L2_ARB_TOKEN_ADDRESS = 0x912CE59144191C1204E64559FE8253a0e49E6548;

    address public constant L2_CORE_GOVERNOR = 0xf07DeD9dC292157749B6Fd268E37DF6EA38395B9;
    address public constant L2_CORE_GOVERNOR_TIMELOCK = 0x34d45e99f7D8c45ed05B5cA72D54bbD1fb3F98f0;
    address public constant L2_TREASURY_GOVERNOR = 0x789fC99093B09aD01C34DC7251D0C89ce743e5a4;
    address public constant L2_TREASURY_GOVERNOR_TIMELOCK =
        0xbFc1FECa8B09A5c5D3EFfE7429eBE24b9c09EF58;
    address public constant L2_PROXY_ADMIN = 0xdb216562328215E010F819B5aBe947bad4ca961e;

    address public constant L2_ARB_SYS = 0x0000000000000000000000000000000000000064;
    address public constant L2_ARB_TREASURY_FIXED_DELEGATE =
        0xF3FC178157fb3c87548bAA86F9d24BA38E649B58;
    address public constant L2_ARB_RETRYABLE_TX = 0x000000000000000000000000000000000000006E;
    address public constant L2_SECURITY_COUNCIL_9 = 0x423552c0F05baCCac5Bfa91C6dCF1dc53a0A1641;

    address public constant L1_TIMELOCK = 0xE6841D92B0C345144506576eC13ECf5103aC7f49;
    uint256 public constant L1_TIMELOCK_MIN_DELAY = 259_200;
    address public constant L1_ARB_ONE_DELAYED_INBOX = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f;

    address public constant L2_CORE_GOVERNOR_NEW_DEPLOY = 0x7796F378B3c56ceD57350B938561D8c52256456b;
    address public constant L2_TREASURY_GOVERNOR_NEW_DEPLOY =
        0x4fd1216c8b5E72b22785169Ae5C1e8f3b30C19E4;
    bool public constant UPGRADE_PROPOSAL_PASSED_ONCHAIN = false; // TODO: Update after the upgrade proposal is passed.

    address public constant L2_UPGRADE_EXECUTOR = 0xCF57572261c7c2BCF21ffD220ea7d1a27D40A827;

    address public constant RETRYABLE_TICKET_MAGIC = 0xa723C008e76E379c55599D2E4d93879BeaFDa79C;

    address public constant EXCLUDE_ADDRESS = address(0xA4b86);
    uint256 public constant QUORUM_DENOMINATOR = 10_000;

    bytes32 public constant TIMELOCK_PROPOSER_ROLE =
        0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1;

    uint8 public constant VOTE_TYPE_FRACTIONAL = 255;

    // These values match the current production values for both governors. Note that they are expressed in L1 blocks,
    // with an assumed 12 second block time, because on Arbitrum, block.number returns the number of the L1.
    uint48 public constant INITIAL_VOTING_DELAY = 21_600; // 3 days
    uint32 public constant INITIAL_VOTING_PERIOD = 100_800; // 14 days
    uint48 public constant INITIAL_VOTE_EXTENSION = 14_400; // 2 days

    // This value matches the current production value for both governors. 1M Arb in raw decimals.
    uint256 public constant INITIAL_PROPOSAL_THRESHOLD = 1_000_000_000_000_000_000_000_000;

    address[] public _majorDelegates;

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    enum VoteType {
        Against,
        For,
        Abstain
    }

    constructor() {
        _majorDelegates = new address[](18);
        _majorDelegates[0] = 0x1B686eE8E31c5959D9F5BBd8122a58682788eeaD; // L2BEAT
        _majorDelegates[1] = 0xF4B0556B9B6F53E00A1FDD2b0478Ce841991D8fA; // olimpio
        _majorDelegates[2] = 0x11cd09a0c5B1dc674615783b0772a9bFD53e3A8F; // Gauntlet
        _majorDelegates[3] = 0xB933AEe47C438f22DE0747D57fc239FE37878Dd1; // Wintermute
        _majorDelegates[4] = 0x0eB5B03c0303f2F47cD81d7BE4275AF8Ed347576; // Treasure
        _majorDelegates[5] = 0xF92F185AbD9E00F56cb11B0b709029633d1E37B4; //
        _majorDelegates[6] = 0x186e505097BFA1f3cF45c2C9D7a79dE6632C3cdc;
        _majorDelegates[7] = 0x5663D01D8109DDFC8aACf09fBE51F2d341bb3643;
        _majorDelegates[8] = 0x2ef27b114917dD53f8633440A7C0328fef132e2F; // MUX Protocol
        _majorDelegates[9] = 0xE48C655276C23F1534AE2a87A2bf8A8A6585Df70; // ercwl
        _majorDelegates[10] = 0x8A3e9846df0CDc723C06e4f0C642ffFF82b54610;
        _majorDelegates[11] = 0xAD16ebE6FfC7d96624A380F394cD64395B0C6144; // DK (Premia)
        _majorDelegates[12] = 0xA5dF0cf3F95C6cd97d998b9D990a86864095d9b0; // Blockworks Research
        _majorDelegates[13] = 0x839395e20bbB182fa440d08F850E6c7A8f6F0780; // Griff Green
        _majorDelegates[14] = 0x2e3BEf6830Ae84bb4225D318F9f61B6b88C147bF; // Camelot
        _majorDelegates[15] = 0x8F73bE66CA8c79382f72139be03746343Bf5Faa0; // mihal.eth
        _majorDelegates[16] = 0xb5B069370Ef24BC67F114e185D185063CE3479f8; // Frisson
        _majorDelegates[17] = 0xdb5781a835b60110298fF7205D8ef9678Ff1f800; // yoav.eth
    }
}
