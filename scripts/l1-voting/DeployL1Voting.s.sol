// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {
    IVotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

import {ProofHelper} from "src/l1-voting/ProofHelper.sol";
import {DelegateMapping} from "src/l1-voting/DelegateMapping.sol";
import {L2StateMirror} from "src/l1-voting/L2StateMirror.sol";
import {VotingTokenMirror} from "src/l1-voting/VotingTokenMirror.sol";
import {L1ArbitrumGovernor} from "src/l1-voting/L1ArbitrumGovernor.sol";
import {ArbitrumTimelock} from "src/ArbitrumTimelock.sol";

bytes32 constant SALT = 0;
address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

// mainnet addresses
address constant L1_PROXY_ADMIN = 0x5613AF0474EB9c528A34701A5b1662E3C8FA0678; // owned by the L1 UpgradeExecutor
address constant L2_PROXY_ADMIN = 0xdb216562328215E010F819B5aBe947bad4ca961e; // owned by the Arb One UpgradeExecutor
address constant L1_UPGRADE_EXECUTOR = 0x3ffFbAdAF827559da092217e474760E2b2c3CeDd;
address constant ARB1_ROLLUP = 0x4DCeB440657f21083db8aDd07665f8ddBe1DCfc0;
address constant L2_ARB_TOKEN = 0x912CE59144191C1204E64559FE8253a0e49E6548;

// ARB token / DelegateMapping storage layout, cross-checked against live state by
// test/l1-voting/fixtures/genL2StateMirrorFixture.ts
uint256 constant DELEGATE_CHECKPOINTS_SLOT = 255;
uint256 constant TOTAL_DELEGATION_SLOT = 356;
uint256 constant DELEGATE_MAPPING_CLAIMED_SLOT = 0;

// governor params, in ~12s L1 blocks; L2 core governor values except the 17 day voting delay
// (3 days L2 reaction time + 14 days worst case assertion confirmation) and the 21 day voting
// period (14 days + 7 day censorship budget). See docs/l1-voting.md#key-durations.
uint256 constant VOTING_DELAY = 122_400; // 17 days
uint256 constant VOTING_PERIOD = 151_200; // 21 days
uint256 constant QUORUM_NUMERATOR = 5000; // 50% of total delegation (denominator 10000)
uint256 constant PROPOSAL_THRESHOLD = 1_000_000 ether;
uint64 constant MIN_PERIOD_AFTER_QUORUM = 14_400; // 2 days
uint256 constant MIN_QUORUM = 150_000_000 ether;
uint256 constant MAX_QUORUM = 450_000_000 ether;
// max age of the threshold block named in propose(); ample time to checkpoint an assertion,
// prove the proposer's votes against it, and land the propose tx
uint256 constant MAX_PROPOSAL_BLOCK_LOOKBACK = 300; // 1 hour

// The timelock delay is set to 25 days, equal to the worst case assertion confirmation time
// of 14 days plus the 11 day reaction window the L2 path gives (L2 timelock 8 days plus L1
// timelock 3 days). This preserves users' ability to react to a malicious proposal and exit
// the chain. See docs/l1-voting.md#key-durations and docs/overview.md#proposal-delays.
uint256 constant TIMELOCK_MIN_DELAY = 25 days;

/// @notice Address of the L2 DelegateMapping proxy as deployed by DeployL2. Computable on either
///         chain since both the implementation and proxy are CREATE2 deploys with fixed inputs.
function predictL2DelegateMappingProxy() pure returns (address) {
    address impl = Create2.computeAddress(
        SALT, keccak256(type(DelegateMapping).creationCode), CREATE2_DEPLOYER
    );
    bytes memory initCode = abi.encodePacked(
        type(TransparentUpgradeableProxy).creationCode, abi.encode(impl, L2_PROXY_ADMIN, bytes(""))
    );
    return Create2.computeAddress(SALT, keccak256(initCode), CREATE2_DEPLOYER);
}

/// @notice Deploys and wires the full L1 side of the L1 voting system.
contract L1VotingFactory {
    address public immutable proofHelper;
    address public immutable delegateMapping;
    address public immutable stateMirror;
    address public immutable votingTokenMirror;
    address public immutable timelock;
    address public immutable governor;

    constructor(address l2DelegateMapping) {
        proofHelper = _proxy(address(new ProofHelper()));
        delegateMapping = _proxy(address(new DelegateMapping()));
        stateMirror = _proxy(
            address(
                new L2StateMirror(
                    proofHelper,
                    L2_ARB_TOKEN,
                    DELEGATE_CHECKPOINTS_SLOT,
                    TOTAL_DELEGATION_SLOT,
                    l2DelegateMapping,
                    DELEGATE_MAPPING_CLAIMED_SLOT,
                    ARB1_ROLLUP
                )
            )
        );
        votingTokenMirror = _proxy(address(new VotingTokenMirror(stateMirror, delegateMapping)));

        governor = _proxy(address(new L1ArbitrumGovernor()));

        address[] memory proposers = new address[](1);
        proposers[0] = governor;
        timelock = _proxy(address(new ArbitrumTimelock()));
        ArbitrumTimelock(payable(timelock)).initialize(
            TIMELOCK_MIN_DELAY, proposers, new address[](1)
        );

        L1ArbitrumGovernor(payable(governor)).initialize({
            _token: IVotesUpgradeable(votingTokenMirror),
            _timelock: TimelockControllerUpgradeable(payable(timelock)),
            _owner: L1_UPGRADE_EXECUTOR,
            _votingDelay: VOTING_DELAY,
            _votingPeriod: VOTING_PERIOD,
            _quorumNumerator: QUORUM_NUMERATOR,
            _proposalThreshold: PROPOSAL_THRESHOLD,
            _minPeriodAfterQuorum: MIN_PERIOD_AFTER_QUORUM,
            _minimumQuorum: MIN_QUORUM,
            _maximumQuorum: MAX_QUORUM,
            _maxProposalBlockLookback: MAX_PROPOSAL_BLOCK_LOOKBACK
        });

        // initializing the timelock granted this factory its admin role; hand admin to the DAO
        // and revoke it from the timelock itself and this factory, as in L1GovernanceFactory
        ArbitrumTimelock tl = ArbitrumTimelock(payable(timelock));
        bytes32 adminRole = tl.TIMELOCK_ADMIN_ROLE();
        bytes32 cancellerRole = tl.CANCELLER_ROLE();
        tl.grantRole(adminRole, L1_UPGRADE_EXECUTOR);
        tl.grantRole(cancellerRole, L1_UPGRADE_EXECUTOR);
        tl.revokeRole(adminRole, timelock);
        tl.revokeRole(adminRole, address(this));
    }

    function _proxy(address impl) private returns (address) {
        return address(new TransparentUpgradeableProxy(impl, L1_PROXY_ADMIN, ""));
    }
}

/// Usage:
///   forge script scripts/l1-voting/DeployL1Voting.s.sol:DeployL2 --rpc-url $ARB_URL --broadcast
///   forge script scripts/l1-voting/DeployL1Voting.s.sol:DeployL1 --rpc-url $ETH_URL --broadcast
/// The two runs are independent; DeployL1 references the L2 DelegateMapping by its predicted
/// CREATE2 address. After deployment the DAO must:
/// - Grant EXECUTOR_ROLE on the L1 UpgradeExecutor to the new timelock.
/// - Grant EXECUTOR_ROLE on the L2 UpgradeExecutor to the alias of the new timelock.
/// The L2 side mapping should be deployed and populated well before the L1 side of the
/// system is live. This prevents a situation where a malicious proposal is created on
/// L1 which forces delegates to scramble to update their claims.
contract DeployL2 is Script {
    function run() external {
        vm.startBroadcast();
        DelegateMapping impl = new DelegateMapping{salt: SALT}();
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy{salt: SALT}(address(impl), L2_PROXY_ADMIN, "");
        vm.stopBroadcast();

        require(address(proxy) == predictL2DelegateMappingProxy(), "L2 proxy address mismatch");
        console.log("L2 DelegateMapping:", address(proxy));
    }
}

contract DeployL1 is Script {
    function run() external {
        require(CREATE2_DEPLOYER == CREATE2_FACTORY, "CREATE2 deployer mismatch");
        vm.startBroadcast();
        L1VotingFactory factory = new L1VotingFactory{salt: SALT}(predictL2DelegateMappingProxy());
        vm.stopBroadcast();

        console.log("L1VotingFactory:    ", address(factory));
        console.log("ProofHelper:        ", factory.proofHelper());
        console.log("L1 DelegateMapping: ", factory.delegateMapping());
        console.log("L2StateMirror:      ", factory.stateMirror());
        console.log("VotingTokenMirror:  ", factory.votingTokenMirror());
        console.log("Timelock:           ", factory.timelock());
        console.log("L1ArbitrumGovernor: ", factory.governor());
        console.log("L2 DelegateMapping (predicted):", predictL2DelegateMappingProxy());
    }
}
