// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../L1ArbitrumMessenger.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/ISecurityCouncilUpgradeExectutor.sol";
import "./interfaces/IL1SecurityCouncilUpdateRouter.sol";

import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../ArbitrumTimelock.sol";

interface IInboxSubmissionFee {
    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee)
        external
        view
        returns (uint256);
}

/// @notice Receives security council updatees from the Security Council manager and forwards them to
/// the L1 security council and all L2 security councils
contract L1SecurityCouncilUpdateRouter is
    L1ArbitrumMessenger,
    Initializable,
    OwnableUpgradeable,
    ArbitrumTimelock,
    IL1SecurityCouncilUpdateRouter
{
    address public governanceChainInbox;
    address public l2SecurityCouncilManager;
    address public l1SecurityCouncilUpgradeExecutor;

    GovernedSecurityCouncil[] public governedSecurityCouncils;

    event SecurityCouncilRegistered(
        uint256 chainID, address inbox, address securityCouncilUpgradeExecutor
    );

    constructor() {
        _disableInitializers();
    }

    /// @notice initialize the L1SecurityCouncilUpdateRouter
    /// @param _governanceChainInbox the address of the governance chain inbox
    /// @param _l1SecurityCouncilUpgradeExecutor the address of the L1 security council upgrade executor
    /// @param _l2SecurityCouncilManager L2 address of security council manager on governance chain
    /// @param _owner the owner of the contract
    /// @param _minDelay minimum timelock delay
    function initialize(
        address _governanceChainInbox,
        address _l1SecurityCouncilUpgradeExecutor,
        address _l2SecurityCouncilManager,
        GovernedSecurityCouncil[] memory _initialGovernedSecurityCouncils,
        address _owner,
        uint256 _minDelay
    ) external initializer onlyOwner {
        governanceChainInbox = _governanceChainInbox;
        l2SecurityCouncilManager = _l2SecurityCouncilManager;
        l1SecurityCouncilUpgradeExecutor = _l1SecurityCouncilUpgradeExecutor;
        for (uint256 i = 0; i < _initialGovernedSecurityCouncils.length; i++) {
            _registerSecurityCouncil(_initialGovernedSecurityCouncils[i]);
        }
        transferOwnership(_owner);

        // bridge (via L2 to L1 message) has proposer role
        address[] memory proposers;
        proposers[0] = address(getBridge(_governanceChainInbox));

        // execution is permissionless
        address[] memory executors;
        executors[0] = address(0);

        __ArbitrumTimelock_init(_minDelay, proposers, executors);
    }

    modifier onlyFromL2SecurityCouncilManager() {
        address govChainBridge = address(getBridge(governanceChainInbox));
        require(msg.sender == govChainBridge, "L1SecurityCouncilUpdateRouter: not from bridge");

        address l2ToL1Sender = super.getL2ToL1Sender(governanceChainInbox);
        require(
            l2ToL1Sender == l2SecurityCouncilManager,
            "L1SecurityCouncilUpdateRouter: not from SecurityCouncilManager"
        );
        _;
    }

    /// @notice overridden; proposals can only be scheduled via scheduleUpdateMembers
    function schedule(
        address,
        uint256,
        bytes calldata,
        bytes32,
        bytes32,
        uint256
    ) public override {
        revert("L1SecurityCouncilUpdateRouter: schedule not callable externally");
    }

    /// @notice overridden; proposals can only be scheduled via scheduleUpdateMembers
    function scheduleBatch(
        address[] calldata __,
        uint256[] calldata ___,
        bytes[] calldata ____,
        bytes32 _____,
        bytes32 ______,
        uint256 _______
    ) public virtual override {
        revert("L1SecurityCouncilUpdateRouter: schedulebatch not callable externally");
    }

    /// @notice schedule a security council member update. callable by the security council manager on L2
    /// @param _membersData data in the form abi.encode(membersToAdd, membersToRemove)
    function scheduleUpdateMembers(bytes calldata _membersData)
        external
        onlyFromL2SecurityCouncilManager
    {
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, block.number, _membersData));
        TimelockControllerUpgradeable.schedule(
            address(this), 0, _membersData, bytes32(0), salt, getMinDelay()
        );
    }

    /// @notice execute a security council member update.
    /// @param __ unused param
    /// @param ___ unused param
    /// @param _membersData data in the form abi.encode(membersToAdd, membersToRemove)
    function _execute(address __, uint256 ___, bytes calldata _membersData) internal override {
        (address[] memory _membersToAdd, address[] memory _membersToRemove) =
            abi.decode(_membersData, (address[], address[]));
        // update l1 security council
        ISecurityCouncilUpgradeExectutor(l1SecurityCouncilUpgradeExecutor).updateMembers(
            _membersToAdd, _membersToRemove
        );

        bytes memory l2CallData = abi.encodeWithSelector(
            ISecurityCouncilUpgradeExectutor.updateMembers.selector, _membersToAdd, _membersToRemove
        );

        // update all l2 security councils
        for (uint256 i = 0; i < governedSecurityCouncils.length; i++) {
            GovernedSecurityCouncil memory securityCouncilData = governedSecurityCouncils[i];
            uint256 submissionCost = IInboxSubmissionFee(securityCouncilData.inbox)
                .calculateRetryableSubmissionFee(l2CallData.length, block.basefee);

            sendTxToL2CustomRefund({
                _inbox: securityCouncilData.inbox, // target inbox
                _to: securityCouncilData.securityCouncilUpgradeExecutor, // target l2 address
                _refundTo: tx.origin, //   fee refund address, for excess basefee TODO: better option?
                _user: address(0xdead), //there is no call value, and nobody should be able to cancel
                _l1CallValue: msg.value, // L1 callvalue
                _l2CallValue: 0, // L2 callvalue
                // TODO possibly controversial: for each of param passing, don't attempt auto-execution
                _l2GasParams: L2GasParams({
                    _maxSubmissionCost: submissionCost,
                    _maxGas: 0,
                    _gasPriceBid: 0
                }),
                _data: l2CallData
            });
        }
    }

    /// @notice Register new DAO governed security council. Callable by DAO.
    /// @param _securityCouncilData new governed securityCouncil
    function registerSecurityCouncil(GovernedSecurityCouncil memory _securityCouncilData)
        external
        onlyOwner
    {
        _registerSecurityCouncil(_securityCouncilData);
    }

    /// @notice remove security council so it's no longer updated / governed
    /// @param index index of council to remove
    function removeSecurityCouncil(uint256 index) external onlyOwner returns (bool) {
        GovernedSecurityCouncil storage lastSecurityCouncil =
            governedSecurityCouncils[governedSecurityCouncils.length - 1];

        governedSecurityCouncils[index] = lastSecurityCouncil;
        governedSecurityCouncils.pop();
        return true;
    }

    function _registerSecurityCouncil(GovernedSecurityCouncil memory _securityCouncilData)
        internal
    {
        require(
            Address.isContract(_securityCouncilData.inbox),
            "L1SecurityCouncilUpdateRouter: inbox not contract"
        );
        require(
            _securityCouncilData.securityCouncilUpgradeExecutor != address(0),
            "L1SecurityCouncilUpdateRouter: zero securityCouncilUpgradeExecutor"
        );
        require(_securityCouncilData.chainID != 0, "L1SecurityCouncilUpdateRouter: zero chainID");

        governedSecurityCouncils.push(_securityCouncilData);
        emit SecurityCouncilRegistered(
            _securityCouncilData.chainID,
            _securityCouncilData.inbox,
            _securityCouncilData.securityCouncilUpgradeExecutor
        );
    }
}
