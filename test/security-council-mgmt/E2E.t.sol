// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "@offchainlabs/upgrade-executor/src/UpgradeExecutor.sol";
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
import "../util/DeployGnosisWithModule.sol";
import "../../src/security-council-mgmt/Common.sol";
import "./governors/SecurityCouncilNomineeElectionGovernor.t.sol";
import "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";

contract ArbSysMock {
    event ArbSysL2ToL1Tx(address from, address to, uint256 value, bytes data);

    uint256 counter;

    struct L2ToL1Tx {
        address from;
        address to;
        uint256 value;
        bytes data;
    }

    L2ToL1Tx[] public txs;

    function sendTxToL1(address destination, bytes calldata calldataForL1)
        external
        payable
        returns (uint256 exitNum)
    {
        exitNum = counter;
        counter = exitNum + 1;
        txs.push(L2ToL1Tx(msg.sender, destination, msg.value, calldataForL1));
        emit ArbSysL2ToL1Tx(msg.sender, destination, msg.value, calldataForL1);
        return exitNum;
    }

    function getTx(uint256 index) public view returns (L2ToL1Tx memory) {
        return txs[index];
    }
}

library Parser {
    // create a struct for all the arguments to the scheduleBatch function
    struct ScheduleBatchArgs {
        address[] targets;
        uint256[] values;
        bytes[] payloads;
        bytes32 predecessor;
        bytes32 salt;
        uint256 delay;
    }

    function scheduleBatchArgs(bytes calldata data)
        public
        pure
        returns (ScheduleBatchArgs memory)
    {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads,
            bytes32 predecessor,
            bytes32 salt,
            uint256 delay
        ) = abi.decode(data[4:], (address[], uint256[], bytes[], bytes32, bytes32, uint256));

        return ScheduleBatchArgs(targets, values, payloads, predecessor, salt, delay);
    }
}

contract E2E is Test, DeployGnosisWithModule {
    function applyL1ToL2Alias(address l1Address) internal pure returns (address) {
        return AddressAliasHelper.applyL1ToL2Alias(l1Address);
    }

    UpgradeExecutor upExecLogic = new UpgradeExecutor();
    L2ArbitrumGovernor arbGovLogic = new L2ArbitrumGovernor();
    ArbitrumTimelock arbTimelockLogic = new ArbitrumTimelock();
    FixedDelegateErc20Wallet fWalletLogic = new FixedDelegateErc20Wallet();
    L2ArbitrumToken l2TokenLogic = new L2ArbitrumToken();

    // owners
    address member1 = vm.addr(637);
    address member2 = vm.addr(638);
    address member3 = vm.addr(639);
    address member4 = vm.addr(640);
    address member5 = vm.addr(641);
    address member6 = vm.addr(642);
    address member7 = vm.addr(643);
    address member8 = vm.addr(644);
    address member9 = vm.addr(645);
    address member10 = vm.addr(646);
    address member11 = vm.addr(647);
    address member12 = vm.addr(648);
    address member13 = vm.addr(649);
    address member14 = vm.addr(650);
    address member15 = vm.addr(651);
    address member16 = vm.addr(652);
    address member17 = vm.addr(653);
    address member18 = vm.addr(654);

    

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
        member12
    ];
    address[] cohort1 = [member1, member2, member3, member4, member5, member6];
    address[] cohort2 = [member7, member8, member9, member10, member11, member12];
    address[] newCohort1 = [member13, member14, member15, member16, member17, member18];

    uint256 secCouncilThreshold = 9;

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
    address novaEmergencyCouncil = address(deploySafe(members, secCouncilThreshold, address(0)));
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

    uint256 removalGovVotingDelay = 47;
    uint256 removalGovVotingPeriod = 48;
    uint256 removalGovQuorumNumerator = 200;
    uint256 removalGovProposalThreshold = 10e5;
    uint256 removalGovVoteSuccessNumerator = 201;
    uint64 removalGovMinPeriodAfterQuorum = 49;
    uint256 removalProposalExpirationBlocks = 139;

    uint256 nomineeVettingDuration = 100;
    address nomineeVetter = address(437);
    uint256 nomineeQuorumNumerator = 20;
    uint256 nomineeVotingPeriod = 51;
    uint256 memberVotingPeriod = 53;
    uint256 fullWeightDuration = 39;
    Date nominationStart = Date(1988, 1, 1, 1);

    uint256 chain1Id = 937;
    uint256 chain2Id = 837;
    uint256 chainNovaId = 737;

    function checkSafeUpdated(
        GnosisSafeL2 safe,
        address[] memory oldCohort1,
        address[] memory oldCohort2,
        address[] memory newCohort,
        uint256 threshold
    ) internal view {
        address[] memory currentOwners = safe.getOwners();
        require(currentOwners.length == 12, "not 12 owners");
        require(safe.getThreshold() == threshold, "threshold changed");
        // check that each cohort1 is a not an owner of moduleL1Safe
        for (uint256 i = 0; i < oldCohort1.length; i++) {
            require(!safe.isOwner(oldCohort1[i]), "old cohort 1 member not removed");
        }
        for (uint256 i = 0; i < oldCohort2.length; i++) {
            require(safe.isOwner(oldCohort2[i]), "old cohort 2 member missing");
        }
        for (uint256 i = 0; i < newCohort.length; i++) {
            require(safe.isOwner(newCohort[i]), "new cohort 1 member not added");
        }
    }

    struct DeployData {
        L2GovernanceFactory l2GovFac;
        L1GovernanceFactory l1GovFac;
        L2AddressRegistry l2AddressRegistry;
        L2SecurityCouncilMgmtFactory secFac;
        GnosisSafeL2 moduleL2Safe;
        GnosisSafeL2 moduleNovaSafe;
        GnosisSafeL2 moduleL1Safe;
        GnosisSafeL2 moduleL2SafeNonEmergency;
        SecurityCouncilMemberSyncAction l2UpdateAction;
        SecurityCouncilMemberSyncAction novaUpdateAction;
        SecurityCouncilMemberSyncAction l1UpdateAction;
        SecurityCouncilData[] councilData;
        ChainAndUpExecLocation[] cExecLocs;
        L2SecurityCouncilMgmtFactory.DeployedContracts secDeployedContracts;
        InboxMock inbox;
        InboxMock novaInbox;
        L1ArbitrumTimelock l1Timelock;
        UpgradeExecutor l1Executor;
        address[] newMembers;
        address to;
        bytes data;
        address novaExecutor;
    }

    function deployNova(address l1Timelock) internal returns (address) {
        ProxyAdmin novaAdmin = new ProxyAdmin();
        UpgradeExecutor novaExecutorLogic = new UpgradeExecutor();
        UpgradeExecutor novaExecutor = UpgradeExecutor(
            address(
                new TransparentUpgradeableProxy(
                address(novaExecutorLogic),
                address(novaAdmin),
                ""
                )
            )
        );
        address[] memory executors = new address[](2);
        executors[0] = applyL1ToL2Alias(l1Timelock);
        executors[1] = novaEmergencyCouncil;
        novaExecutor.initialize(address(novaExecutor), executors);

        novaAdmin.transferOwnership(address(novaExecutor));

        return address(novaExecutor);
    }

    function deploy() internal {
        // set the current block
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

        vars.inbox = new InboxMock(address(0));
        vars.novaInbox = new InboxMock(address(0));
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

        vars.l2GovFac.deployStep3(applyL1ToL2Alias(address(vars.l1Timelock)));

        vars.novaExecutor = deployNova(address(vars.l1Timelock));

        // deploy sec council
        vars.l2AddressRegistry = new L2AddressRegistry(
            IL2ArbitrumGoverner(address(l2DeployedCoreContracts.coreGov)),
            IL2ArbitrumGoverner(address(l2DeployedTreasuryContracts.treasuryGov)),
            IFixedDelegateErc20Wallet(address(l2DeployedTreasuryContracts.arbTreasury)),
            IArbitrumDAOConstitution(address(l2DeployedCoreContracts.arbitrumDAOConstitution))
        );

        vars.secFac = new L2SecurityCouncilMgmtFactory();

        vars.moduleL2Safe = GnosisSafeL2(
            payable(
                deploySafe(members, secCouncilThreshold, address(l2DeployedCoreContracts.executor))
            )
        );
        vars.moduleL2SafeNonEmergency = GnosisSafeL2(
            payable(
                deploySafe(members, secCouncilThreshold, address(l2DeployedCoreContracts.executor))
            )
        );
        vars.moduleL1Safe = GnosisSafeL2(
            payable(deploySafe(members, secCouncilThreshold, address(vars.l1Executor)))
        );
        vars.moduleNovaSafe = GnosisSafeL2(
            payable(deploySafe(members, secCouncilThreshold, address(vars.novaExecutor)))
        );

        vars.l2UpdateAction = new SecurityCouncilMemberSyncAction(new KeyValueStore());
        vars.novaUpdateAction = new SecurityCouncilMemberSyncAction(new KeyValueStore());
        vars.l1UpdateAction = new SecurityCouncilMemberSyncAction(new KeyValueStore());

        vars.councilData = new SecurityCouncilData[](4);
        vars.councilData[0] =
            SecurityCouncilData(address(vars.moduleL2Safe), address(vars.l2UpdateAction), chain2Id);
        vars.councilData[1] = SecurityCouncilData(
            address(vars.moduleL2SafeNonEmergency), address(vars.l2UpdateAction), chain2Id
        );
        vars.councilData[2] =
            SecurityCouncilData(address(vars.moduleL1Safe), address(vars.l1UpdateAction), chain1Id);
        vars.councilData[3] = SecurityCouncilData(
            address(vars.moduleNovaSafe), address(vars.novaUpdateAction), chainNovaId
        );

        vars.cExecLocs = new ChainAndUpExecLocation[](3);
        vars.cExecLocs[0] =
            ChainAndUpExecLocation(chain1Id, UpExecLocation(address(0), address(vars.l1Executor)));
        vars.cExecLocs[1] = ChainAndUpExecLocation(
            chain2Id, UpExecLocation(address(vars.inbox), address(l2DeployedCoreContracts.executor))
        );
        vars.cExecLocs[2] = ChainAndUpExecLocation(
            chainNovaId, UpExecLocation(address(vars.novaInbox), address(vars.novaExecutor))
        );

        {
            DeployParams memory secDeployParams = DeployParams({
                upgradeExecutors: vars.cExecLocs,
                govChainEmergencySecurityCouncil: address(vars.moduleL2Safe),
                l1ArbitrumTimelock: address(vars.l1Timelock),
                l2CoreGovTimelock: address(l2DeployedCoreContracts.coreTimelock),
                govChainProxyAdmin: address(l2DeployedCoreContracts.proxyAdmin),
                secondCohort: cohort2,
                firstCohort: cohort1,
                l2UpgradeExecutor: address(l2DeployedCoreContracts.executor),
                arbToken: address(l2DeployedCoreContracts.token),
                l1TimelockMinDelay: l1MinTimelockDelay,
                removalGovVotingDelay: removalGovVotingDelay,
                removalGovVotingPeriod: removalGovVotingPeriod,
                removalGovQuorumNumerator: removalGovQuorumNumerator,
                removalGovProposalThreshold: removalGovProposalThreshold,
                removalGovVoteSuccessNumerator: removalGovVoteSuccessNumerator,
                removalGovMinPeriodAfterQuorum: removalGovMinPeriodAfterQuorum,
                removalProposalExpirationBlocks: removalProposalExpirationBlocks,
                securityCouncils: vars.councilData,
                firstNominationStartDate: nominationStart,
                nomineeVettingDuration: nomineeVettingDuration,
                nomineeVetter: nomineeVetter,
                nomineeQuorumNumerator: nomineeQuorumNumerator,
                nomineeVotingPeriod: nomineeVotingPeriod,
                memberVotingPeriod: memberVotingPeriod,
                fullWeightDuration: fullWeightDuration
            });

            ContractImplementations memory contractImpls = ContractImplementations({
                securityCouncilManager: address(new SecurityCouncilManager()),
                securityCouncilMemberRemoverGov: address(new SecurityCouncilMemberRemovalGovernor()),
                nomineeElectionGovernor: address(new SecurityCouncilNomineeElectionGovernor()),
                memberElectionGovernor: address(new SecurityCouncilMemberElectionGovernor())
            });

            vars.secDeployedContracts = vars.secFac.deploy(secDeployParams, contractImpls);
        }

        L1SCMgmtActivationAction installL1 = new L1SCMgmtActivationAction(
            IGnosisSafe(address(vars.moduleL1Safe)),
            IGnosisSafe(l1EmergencyCouncil),
            secCouncilThreshold,
            IUpgradeExecutor(address(vars.l1Executor)),
            ICoreTimelock(address(vars.l1Timelock))
        );

        // l1 sec council conducts the install
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
            vars.l2AddressRegistry
        );

        vm.prank(l2EmergencyCouncil);
        l2DeployedCoreContracts.executor.execute(
            address(installL2),
            abi.encodeWithSelector(GovernanceChainSCMgmtActivationAction.perform.selector)
        );

        // setup complete, try an election - warp to the next election
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

        // start the election
        uint256 propId = vars.secDeployedContracts.nomineeElectionGovernor.createElection();

        // put contenders up for election
        SigUtils sigUtils = new SigUtils(address(vars.secDeployedContracts.nomineeElectionGovernor));
        for (uint256 i = 0; i < newCohort1.length; i++) {
            uint256 pk = 649 + i; // member 13 - 18 priv keys
            vars.secDeployedContracts.nomineeElectionGovernor.addContender(propId, sigUtils.signAddContenderMessage(propId, pk));
        }

        // vote for them
        vm.roll(block.number + 1);
        for (uint256 i = 0; i < newCohort1.length; i++) {
            vm.prank(l2InitialSupplyRecipient);
            vars.secDeployedContracts.nomineeElectionGovernor.castVoteWithReasonAndParams(
                propId, 1, "vote for a nominee", abi.encode(newCohort1[i], 1 ether)
            );
        }

        {
            // nomination complete - transition to member election
            vm.roll(block.number + nomineeVotingPeriod + nomineeVettingDuration);
            (
                address[] memory targets,
                uint256[] memory values,
                bytes[] memory callDatas,
                string memory description
            ) = vars.secDeployedContracts.nomineeElectionGovernor.getProposeArgs(
                vars.secDeployedContracts.nomineeElectionGovernor.electionCount() - 1
            );
            vars.secDeployedContracts.nomineeElectionGovernor.execute(
                targets, values, callDatas, keccak256(bytes(description))
            );
        }

        // vote for the new members
        vm.roll(block.number + 1);
        for (uint256 i = 0; i < newCohort1.length; i++) {
            address newMember = newCohort1[i];
            vm.prank(l2InitialSupplyRecipient);
            vars.secDeployedContracts.memberElectionGovernor.castVoteWithReasonAndParams(
                propId, 1, "vote for a member", abi.encode(newMember, 1 ether)
            );
        }

        {
            // member election complete - transition to timelock
            vm.roll(block.number + memberVotingPeriod);
            (
                address[] memory targets,
                uint256[] memory values,
                bytes[] memory callDatas,
                string memory description
            ) = vars.secDeployedContracts.nomineeElectionGovernor.getProposeArgs(
                vars.secDeployedContracts.nomineeElectionGovernor.electionCount() - 1
            );
            vars.secDeployedContracts.memberElectionGovernor.execute(
                targets, values, callDatas, keccak256(bytes(description))
            );
        }

        // exec in the l2 timelock
        {
            (address[] memory newMembers, address to, bytes memory data) = vars
                .secDeployedContracts
                .securityCouncilManager
                .getScheduleUpdateInnerData(
                vars.secDeployedContracts.securityCouncilManager.updateNonce()
            );
            vars.newMembers = newMembers;
            vars.to = to;
            vars.data = data;
        }
        vm.warp(block.timestamp + l2MinTimelockDelay);
        vm.etch(address(100), address(new ArbSysMock()).code);
        l2DeployedCoreContracts.coreTimelock.execute(
            vars.to,
            0,
            vars.data,
            0,
            vars.secDeployedContracts.securityCouncilManager.generateSalt(
                vars.newMembers, vars.secDeployedContracts.securityCouncilManager.updateNonce()
            )
        );

        // execute in the outbox mock
        ArbSysMock.L2ToL1Tx memory l2ToL1Tx = ArbSysMock(address(100)).getTx(0);
        vars.inbox.setL2ToL1Sender(l2ToL1Tx.from);
        vm.prank(address(vars.inbox.bridge()));
        address(l2ToL1Tx.to).call{value: l2ToL1Tx.value}(l2ToL1Tx.data);

        // parse the schedule batch args
        Parser.ScheduleBatchArgs memory args = Parser.scheduleBatchArgs(l2ToL1Tx.data);

        // execute in the l1 timelock
        vm.warp(block.timestamp + l1MinTimelockDelay);
        vars.l1Timelock.executeBatch(
            args.targets, args.values, args.payloads, args.predecessor, args.salt
        );

        // check the l1 safe updated
        checkSafeUpdated(vars.moduleL1Safe, cohort1, cohort2, newCohort1, secCouncilThreshold);

        // execute the retryables and check the safes
        InboxMock.RetryableTicket memory ticket1 = vars.inbox.getRetryableTicket(0);
        vm.prank(applyL1ToL2Alias(ticket1.from));
        address(ticket1.to).call{value: ticket1.value}(ticket1.data);
        checkSafeUpdated(vars.moduleL2Safe, cohort1, cohort2, newCohort1, secCouncilThreshold);

        InboxMock.RetryableTicket memory ticket2 = vars.inbox.getRetryableTicket(1);
        vm.prank(applyL1ToL2Alias(ticket2.from));
        address(ticket2.to).call{value: ticket2.value}(ticket2.data);
        checkSafeUpdated(
            vars.moduleL2SafeNonEmergency, cohort1, cohort2, newCohort1, secCouncilThreshold
        );

        InboxMock.RetryableTicket memory ticket3 = vars.novaInbox.getRetryableTicket(0);
        vm.prank(applyL1ToL2Alias(ticket3.from));
        address(ticket3.to).call{value: ticket3.value}(ticket3.data);
        checkSafeUpdated(vars.moduleNovaSafe, cohort1, cohort2, newCohort1, secCouncilThreshold);
    }

    function testE2E() public {
        deploy();
    }
}
