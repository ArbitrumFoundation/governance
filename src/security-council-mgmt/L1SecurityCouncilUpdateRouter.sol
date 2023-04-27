// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../L1ArbitrumMessenger.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/ISecurityCouncilUpgradeExectutor.sol";
import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

interface IInboxSubmissionFee {
    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee)
        external
        view
        returns (uint256);
}

contract L1SecurityCouncilUpdateRouter is L1ArbitrumMessenger, Initializable, OwnableUpgradeable {
    struct L2ChainToUpdate {
        address inbox;
        address securityCouncilUpgradeExecutor;
        uint256 chainID;
    }

    address public governanceChainInbox;
    address public securityCouncilManager;
    address public l1SecurityCouncilUpgradeExecutor;

    L2ChainToUpdate[] public l2ChainsToUpdateArr;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _governanceChainInbox,
        address _l1SecurityCouncilUpgradeExecutor,
        address _securityCouncilManager,
        L2ChainToUpdate[] memory _initiall2ChainsToUpdateArr
    ) external initializer {
        governanceChainInbox = _governanceChainInbox;
        securityCouncilManager = securityCouncilManager;
        l1SecurityCouncilUpgradeExecutor = _l1SecurityCouncilUpgradeExecutor;
        for (uint256 i = 0; i < _initiall2ChainsToUpdateArr.length; i++) {
            _addL2ChainToUpdate(_initiall2ChainsToUpdateArr[i]);
        }
    }

    modifier onlyFromSecurityCouncilManager() {
        address govChainBridge = address(getBridge(governanceChainInbox));
        require(msg.sender == govChainBridge, "L1SecurityCouncilUpdateRouter: not from bridge");

        address l2ToL1Sender = super.getL2ToL1Sender(governanceChainInbox);
        require(
            l2ToL1Sender == securityCouncilManager,
            "L1SecurityCouncilUpdateRouter: not from SecurityCouncilManager"
        );
        _;
    }

    function handleAddMember(address _member) external onlyFromSecurityCouncilManager {
        ISecurityCouncilUpgradeExectutor(l1SecurityCouncilUpgradeExecutor).addMember(_member);

        bytes memory l2CallData =
            abi.encodeWithSelector(ISecurityCouncilUpgradeExectutor.addMember.selector, _member);
        sendToAllL2s(l2CallData);
    }

    function handleRemoveMember(address _member) external onlyFromSecurityCouncilManager {
        ISecurityCouncilUpgradeExectutor(l1SecurityCouncilUpgradeExecutor).removeMember(_member);

        bytes memory l2CallData =
            abi.encodeWithSelector(ISecurityCouncilUpgradeExectutor.removeMember.selector, _member);
        sendToAllL2s(l2CallData);
    }

    function handleUpdateMembers(address[] memory _membersToAdd, address[] memory _membersToRemove)
        external
        onlyFromSecurityCouncilManager
    {
        ISecurityCouncilUpgradeExectutor(l1SecurityCouncilUpgradeExecutor).updateMembers(
            _membersToAdd, _membersToRemove
        );

        bytes memory l2CallData = abi.encodeWithSelector(
            ISecurityCouncilUpgradeExectutor.updateMembers.selector, _membersToAdd, _membersToRemove
        );
        sendToAllL2s(l2CallData);
    }

    function sendToAllL2s(bytes memory l2CallData) internal {
        for (uint256 i = 0; i < l2ChainsToUpdateArr.length; i++) {
            L2ChainToUpdate memory l2ChainToUpdate = l2ChainsToUpdateArr[i];
            uint256 submissionCost = IInboxSubmissionFee(l2ChainToUpdate.inbox)
                .calculateRetryableSubmissionFee(l2CallData.length, block.basefee);

            sendTxToL2CustomRefund(
                l2ChainToUpdate.inbox,
                l2ChainToUpdate.securityCouncilUpgradeExecutor,
                // TODO
                msg.sender,
                address(this),
                msg.value,
                0,
                L2GasParams({_maxSubmissionCost: submissionCost, _maxGas: 0, _gasPriceBid: 0}),
                l2CallData
            );
            // sendTxToL2(l2ChainsToUpdateArr[i].inbox, l2CallData);
        }
    }

    function addL2ChainToUpdate(L2ChainToUpdate memory l2ChainToUpdate) external onlyOwner {
        _addL2ChainToUpdate(l2ChainToUpdate);
    }

    function _addL2ChainToUpdate(L2ChainToUpdate memory l2ChainToUpdate) internal {
        require(l2ChainToUpdate.inbox != address(0), "L1SecurityCouncilUpdateRouter: invalid inbox");
        require(
            l2ChainToUpdate.securityCouncilUpgradeExecutor != address(0),
            "L1SecurityCouncilUpdateRouter: invalid securityCouncilUpgradeExecutor"
        );
        require(l2ChainToUpdate.chainID != 0, "L1SecurityCouncilUpdateRouter: invalid chainID");
        // emit event
        l2ChainsToUpdateArr.push(l2ChainToUpdate);
    }
}
