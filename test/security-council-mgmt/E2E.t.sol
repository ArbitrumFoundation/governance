// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../src/UpgradeExecutor.sol";
import "../../src/ArbitrumTimelock.sol";
import "../../src/L2ArbitrumGovernor.sol";
import "../../src/FixedDelegateErc20Wallet.sol";
import "../../src/L2GovernanceFactory.sol";
import "../../src/L1GovernanceFactory.sol";
import "../../src/security-council-mgmt/factories/L2SecurityCouncilMgmtFactory.sol";
import "../util/InboxMock.sol";
import "../../src/gov-action-contracts/AIPs/SecurityCouncilMgmt/L1SCMgmtActivationAction.sol";
import
    "../../src/gov-action-contracts/AIPs/SecurityCouncilMgmt/GovernanceChainSCMgmtActivationAction.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "../../src/gov-action-contracts/address-registries/L2AddressRegistry.sol";

contract E2E is Test {
    uint160 constant offset = uint160(0x1111000000000000000000000000000000001111);

    function applyL1ToL2Alias(address l1Address) internal pure returns (address) {
        return address(uint160(l1Address) + offset);
    }

    UpgradeExecutor upExecLogic = new UpgradeExecutor();
    L2ArbitrumGovernor arbGovLogic = new L2ArbitrumGovernor();
    ArbitrumTimelock arbTimelockLogic = new ArbitrumTimelock();
    FixedDelegateErc20Wallet fWalletLogic = new FixedDelegateErc20Wallet();
    L2ArbitrumToken l2TokenLogic = new L2ArbitrumToken();

    // owners
    address member1 = address(637);
    address member2 = address(638);
    address member3 = address(639);
    address member4 = address(640);
    address member5 = address(641);
    address member6 = address(642);
    address member7 = address(643);
    address member8 = address(644);
    address member9 = address(645);
    address member10 = address(646);
    address member11 = address(647);
    address member12 = address(648);
    address member13 = address(649);
    address member14 = address(650);
    address member15 = address(651);
    address member16 = address(652);
    address member17 = address(653);
    address member18 = address(654);

    address[] members = [
        member1,
        member2,
        member3,
        member4,
        member5,
        member6,
        member7,
        member8,
        member9,
        member10,
        member11,
        member12,
        member13,
        member14,
        member15,
        member16,
        member17,
        member18
    ];
    address[] cohort1 = [member1, member2, member3, member4, member5, member6];
    address[] cohort2 = [member7, member8, member9, member10, member11, member12];
    address[] newCohort1 = [member13, member14, member15, member16, member17, member18];

    uint256 secCouncilThreshold = 4;

    // token
    address l1Token = address(139);
    uint256 l2TokenInitialSupply = 30 ether;

    // timelock
    uint256 l2MinTimelockDelay = 42;
    uint256 l1MinTimelockDelay = 43;

    // govs
    uint256 votingPeriod = 44;
    uint256 votingDelay = 45;
    uint256 coreQuorumThreshold = 4;
    uint256 treasuryQuorumThreshold = 3;
    uint256 proposalThreshold = 5e6;
    uint64 minPeriodAfterQuorum = 41;

    // councils
    address l2EmergencyCouncil = address(deploySafe(members, secCouncilThreshold, address(0)));
    address l1EmergencyCouncil = address(deploySafe(members, secCouncilThreshold, address(0)));
    address someRando = address(390);
    address l2NonEmergencySecurityCouncil =
        address(deploySafe(members, secCouncilThreshold, address(0)));
    address l2InitialSupplyRecipient = address(456);

    bytes32 constitutionHash = bytes32("0x0123");
    uint256 l2TreasuryMinTimelockDelay = 87;

    DeployCoreParams l2DeployParams = DeployCoreParams({
        _l2MinTimelockDelay: l2MinTimelockDelay,
        _l1Token: l1Token,
        _l2TokenInitialSupply: l2TokenInitialSupply,
        _votingPeriod: votingPeriod,
        _votingDelay: votingDelay,
        _coreQuorumThreshold: coreQuorumThreshold,
        _treasuryQuorumThreshold: treasuryQuorumThreshold,
        _proposalThreshold: proposalThreshold,
        _minPeriodAfterQuorum: minPeriodAfterQuorum,
        _l2NonEmergencySecurityCouncil: l2NonEmergencySecurityCouncil,
        _l2InitialSupplyRecipient: l2InitialSupplyRecipient,
        _l2EmergencySecurityCouncil: l2EmergencyCouncil,
        _constitutionHash: constitutionHash,
        _l2TreasuryMinTimelockDelay: l2TreasuryMinTimelockDelay
    });

    address bridge = address(10_002);

    uint256 removalGovVotingDelay = 47;
    uint256 removalGovVotingPeriod = 48;
    uint256 removalGovQuorumNumerator = 200;
    uint256 removalGovProposalThreshold = 10e5;
    uint256 removalGovVoteSuccessNumerator = 201;
    uint64 removalGovMinPeriodAfterQuorum = 49;

    uint256 nomineeVettingDuration = 100;
    address nomineeVetter = address(437);
    uint256 nomineeQuorumNumerator = 101;
    uint256 nomineeVotingPeriod = 51;
    uint256 memberVotingPeriod = 53;
    uint256 fullWeightDuration = 39;
    SecurityCouncilNomineeElectionGovernorTiming.Date nominationStart =
        SecurityCouncilNomineeElectionGovernorTiming.Date(1988, 1, 1, 1);

    uint256 chain1Id = 937;
    uint256 chain2Id = 837;

    function deploySafe(address[] memory _owners, uint256 _threshold, address _module)
        internal
        returns (GnosisSafeL2)
    {
        // CHRIS: TODO: we should share this
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
        return safe;
    }

    struct DeployData {
        L2GovernanceFactory l2GovFac;
        L1GovernanceFactory l1GovFac;
        L2AddressRegistry l2AddressRegistry;
        L2SecurityCouncilMgmtFactory secFac;
        GnosisSafeL2 moduleL2Safe;
        GnosisSafeL2 moduleL1Safe;
        GnosisSafeL2 moduleL2SafeNonEmergency;
        SecurityCouncilUpgradeAction l2UpdateAction;
        SecurityCouncilUpgradeAction l1UpdateAction;
        SecurityCouncilData[] councilData;
        ChainAndUpExecLocation[] cExecLocs;
        L2SecurityCouncilMgmtFactory.DeployedContracts secDeployedContracts;
        InboxMock inbox;
        L1ArbitrumTimelock l1Timelock;
        UpgradeExecutor l1Executor;
        address[] newMembers;
        address to;
        bytes data;
    }

    function deploy() internal {
        vm.roll(1000);
        DeployData memory vars;

        vars.l2GovFac = new L2GovernanceFactory(
            address(arbTimelockLogic),
            address(arbGovLogic),
            address(arbTimelockLogic),
            address(fWalletLogic),
            address(arbGovLogic),
            address(l2TokenLogic),
            address(upExecLogic)
        );

        vars.l1GovFac = new L1GovernanceFactory();
        (
            DeployedContracts memory l2DeployedCoreContracts,
            DeployedTreasuryContracts memory l2DeployedTreasuryContracts
        ) = vars.l2GovFac.deployStep1(l2DeployParams);

        vars.inbox = new InboxMock(bridge);
        {
            (L1ArbitrumTimelock l1Timelock,, UpgradeExecutor l1Executor) = vars.l1GovFac.deployStep2(
                address(upExecLogic),
                l1MinTimelockDelay,
                address(vars.inbox),
                address(l2DeployedCoreContracts.coreTimelock),
                l1EmergencyCouncil
            );
            vars.l1Timelock = l1Timelock;
            vars.l1Executor = l1Executor;
        }

        vars.l2GovFac.deployStep3(applyL1ToL2Alias(address(vars.inbox)));

        // deploy sec council
        vars.l2AddressRegistry = new L2AddressRegistry(
            IL2ArbitrumGoverner(address(l2DeployedCoreContracts.coreGov)),
            IL2ArbitrumGoverner(address(l2DeployedTreasuryContracts.treasuryGov)),
            IFixedDelegateErc20Wallet(address(l2DeployedTreasuryContracts.arbTreasury)),
            IArbitrumDAOConstitution(address(l2DeployedCoreContracts.arbitrumDAOConstitution))
        );

        vars.secFac = new L2SecurityCouncilMgmtFactory();

        vars.moduleL2Safe =
            deploySafe(members, secCouncilThreshold, address(l2DeployedCoreContracts.executor));
        vars.moduleL2SafeNonEmergency =
            deploySafe(members, secCouncilThreshold, address(l2DeployedCoreContracts.executor));
        vars.moduleL1Safe = deploySafe(members, secCouncilThreshold, address(vars.l1Executor));

        vars.l2UpdateAction = new SecurityCouncilUpgradeAction();
        vars.l1UpdateAction = new SecurityCouncilUpgradeAction();

        vars.councilData = new SecurityCouncilData[](3);
        vars.councilData[0] =
            SecurityCouncilData(address(vars.moduleL2Safe), address(vars.l2UpdateAction), chain2Id);
        vars.councilData[1] = SecurityCouncilData(
            address(vars.moduleL2SafeNonEmergency), address(vars.l2UpdateAction), chain2Id
        );
        vars.councilData[2] =
            SecurityCouncilData(address(vars.moduleL1Safe), address(vars.l1UpdateAction), chain1Id);

        vars.cExecLocs = new ChainAndUpExecLocation[](2);
        vars.cExecLocs[0] =
            ChainAndUpExecLocation(chain1Id, UpExecLocation(address(0), address(vars.l1Executor)));
        vars.cExecLocs[1] = ChainAndUpExecLocation(
            chain2Id, UpExecLocation(address(vars.inbox), address(l2DeployedCoreContracts.executor))
        );

        DeployParams memory secDeployParams = DeployParams({
            _upgradeExecutors: vars.cExecLocs,
            _govChainEmergencySecurityCouncil: address(vars.moduleL2Safe),
            _l1ArbitrumTimelock: address(vars.l1Timelock),
            _l2CoreGovTimelock: address(l2DeployedCoreContracts.coreTimelock),
            _proxyAdmin: address(l2DeployedCoreContracts.proxyAdmin),
            _secondCohort: cohort2,
            _firstCohort: cohort1,
            l2UpgradeExecutor: address(l2DeployedCoreContracts.executor),
            arbToken: address(l2DeployedCoreContracts.token),
            _l1TimelockMinDelay: l1MinTimelockDelay,
            _removalGovVotingDelay: removalGovVotingDelay,
            _removalGovVotingPeriod: removalGovVotingPeriod,
            _removalGovQuorumNumerator: removalGovQuorumNumerator,
            _removalGovProposalThreshold: removalGovProposalThreshold,
            _removalGovVoteSuccessNumerator: removalGovVoteSuccessNumerator,
            _removalGovMinPeriodAfterQuorum: removalGovMinPeriodAfterQuorum,
            _securityCouncils: vars.councilData,
            firstNominationStartDate: nominationStart,
            nomineeVettingDuration: nomineeVettingDuration,
            nomineeVetter: nomineeVetter,
            nomineeQuorumNumerator: nomineeQuorumNumerator,
            nomineeVotingPeriod: nomineeVotingPeriod,
            memberVotingPeriod: memberVotingPeriod,
            _fullWeightDuration: fullWeightDuration
        });

        vars.secDeployedContracts = vars.secFac.deploy(secDeployParams);

        // now install it - CHRIS: TODO: do this via a governance proposal
        // CHRIS: TODO: add nova
        L1SCMgmtActivationAction installL1 = new L1SCMgmtActivationAction(
            IGnosisSafe(address(vars.moduleL1Safe)),
            IGnosisSafe(l1EmergencyCouncil),
            secCouncilThreshold,
            IUpgradeExecutor(address(vars.l1Executor)),
            ICoreTimelock(address(vars.l1Timelock))
        );

        vm.prank(l1EmergencyCouncil);
        vars.l1Executor.execute(
            address(installL1), abi.encodeWithSelector(L1SCMgmtActivationAction.perform.selector)
        );

        GovernanceChainSCMgmtActivationAction installL2 = new GovernanceChainSCMgmtActivationAction(
            IGnosisSafe(address(vars.moduleL2Safe)),
            IGnosisSafe(address(vars.moduleL2SafeNonEmergency)),
            IGnosisSafe(l2EmergencyCouncil),
            IGnosisSafe(l2NonEmergencySecurityCouncil),
            secCouncilThreshold,
            secCouncilThreshold,
            address(vars.secDeployedContracts.securityCouncilManager),
            vars.l2AddressRegistry,
            constitutionHash
        );

        vm.prank(l2EmergencyCouncil);
        l2DeployedCoreContracts.executor.execute(
            address(installL2),
            abi.encodeWithSelector(GovernanceChainSCMgmtActivationAction.perform.selector)
        );

        // setup complete, try an election
        vm.warp(
            DateTimeLib.dateTimeToTimestamp({
                year: nominationStart.year,
                month: nominationStart.month,
                day: nominationStart.day,
                hour: nominationStart.hour,
                minute: 0,
                second: 1
            })
        );

        // initial supply recipient delegates to itself
        vm.prank(l2InitialSupplyRecipient);
        l2DeployedCoreContracts.token.delegate(l2InitialSupplyRecipient);

        uint256 propId = vars.secDeployedContracts.nomineeElectionGovernor.createElection();
        vm.roll(block.number + 1);

        for (uint256 i = 0; i < newCohort1.length; i++) {
            address newMember = newCohort1[i];
            vm.prank(newMember);
            vars.secDeployedContracts.nomineeElectionGovernor.addContender(propId);
            vm.prank(l2InitialSupplyRecipient);
            vars.secDeployedContracts.nomineeElectionGovernor.castVoteWithReasonAndParams(
                propId, 0, "vote for a nominee", abi.encode(newMember, 1 ether)
            );
        }

        vm.roll(block.number + nomineeVotingPeriod + nomineeVettingDuration);

        vars.secDeployedContracts.nomineeElectionGovernor.execute(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            keccak256(
                bytes(
                    vars.secDeployedContracts.nomineeElectionGovernor.electionIndexToDescription(
                        vars.secDeployedContracts.nomineeElectionGovernor.electionCount() - 1
                    )
                )
            )
        );

        vm.roll(block.number + 1);

        for (uint256 i = 0; i < newCohort1.length; i++) {
            address newMember = newCohort1[i];
            vm.prank(l2InitialSupplyRecipient);
            vars.secDeployedContracts.memberElectionGovernor.castVoteWithReasonAndParams(
                propId, 0, "vote for a member", abi.encode(newMember, 1 ether)
            );
        }

        vm.roll(block.number + memberVotingPeriod);

        vars.secDeployedContracts.memberElectionGovernor.execute(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            keccak256(
                bytes(
                    vars.secDeployedContracts.nomineeElectionGovernor.electionIndexToDescription(
                        vars.secDeployedContracts.nomineeElectionGovernor.electionCount() - 1
                    )
                )
            )
        );
        {
            (address[] memory newMembers, address to, bytes memory data) = vars.secDeployedContracts.securityCouncilManager.getScheduleUpdateData();
            vars.newMembers = newMembers;
            vars.to = to;
            vars.data = data;
        }

        vm.warp(block.timestamp + l2MinTimelockDelay);
        
        // CHRIS: TODO: use vm.etch to capture the data that's sent to arbsys, and execute it via the outbox

        l2DeployedCoreContracts.coreTimelock.execute(
            vars.to,
            0,
            vars.data,
            0,
            vars.secDeployedContracts.securityCouncilManager.generateSalt(vars.newMembers)
        );


        // call through the outbox - use an outbox mock if necessary
        // execute in the l1 timelock
        // check the new council is set on l1
        // check that correct retryable was set in the l1 inbox
        // execute that retryable on l2
        // check the council is set on l2

        // add a nova instance
    }

    function testE2E() public {
        deploy();
    }
}
