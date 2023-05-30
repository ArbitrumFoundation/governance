// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../L1ArbitrumMessenger.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/ISecurityCouncilUpgradeExectutor.sol";
import "./interfaces/IL1SecurityCouncilUpdateRouter.sol";

import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IInboxSubmissionFee {
    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee)
        external
        view
        returns (uint256);
}

/// @notice Receives security council updatees from the Security Council manager and forwards them to
/// the L1 security council and the non-governance chain governed L2 security councils
contract L1SecurityCouncilUpdateRouter is
    L1ArbitrumMessenger,
    Initializable,
    OwnableUpgradeable,
    IL1SecurityCouncilUpdateRouter
{
    address public governanceChainInbox;
    address public l2SecurityCouncilManager;
    address public l1SecurityCouncilUpgradeExecutor;

    L2ChainToUpdate[] public l2ChainsToUpdateArr;

    event L2ChainRegistered(uint256 chainID, address inbox, address securityCouncilUpgradeExecutor);

    constructor() {
        _disableInitializers();
    }

    /// @notice initialize the L1SecurityCouncilUpdateRouter
    /// @param _governanceChainInbox the address of the governance chain inbox
    /// @param _l1SecurityCouncilUpgradeExecutor the address of the L1 security council upgrade executor
    /// @param _l2SecurityCouncilManager L2 address of security council manager on governance chain
    function initialize(
        address _governanceChainInbox,
        address _l1SecurityCouncilUpgradeExecutor,
        address _l2SecurityCouncilManager,
        L2ChainToUpdate[] memory _initiall2ChainsToUpdateArr,
        address _owner
    ) external initializer onlyOwner {
        governanceChainInbox = _governanceChainInbox;
        l2SecurityCouncilManager = _l2SecurityCouncilManager;
        l1SecurityCouncilUpgradeExecutor = _l1SecurityCouncilUpgradeExecutor;
        for (uint256 i = 0; i < _initiall2ChainsToUpdateArr.length; i++) {
            _registerL2Chain(_initiall2ChainsToUpdateArr[i]);
        }
        transferOwnership(_owner);
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

    /// @notice update l1 security council and send L1 to L2 messages to update security councils for all L2s (except governance chain)
    /// @param _membersToAdd addresses of new members to add to the security council
    /// @param _membersToRemove addresses of members to remove from the security council
    function handleUpdateMembers(address[] memory _membersToAdd, address[] memory _membersToRemove)
        external
        payable
        onlyFromL2SecurityCouncilManager
    {
        // update l1 security council
        ISecurityCouncilUpgradeExectutor(l1SecurityCouncilUpgradeExecutor).updateMembers(
            _membersToAdd, _membersToRemove
        );

        bytes memory l2CallData = abi.encodeWithSelector(
            ISecurityCouncilUpgradeExectutor.updateMembers.selector, _membersToAdd, _membersToRemove
        );

        // update all non-gov-chain l2 security councils
        for (uint256 i = 0; i < l2ChainsToUpdateArr.length; i++) {
            L2ChainToUpdate memory l2ChainToUpdate = l2ChainsToUpdateArr[i];
            uint256 submissionCost = IInboxSubmissionFee(l2ChainToUpdate.inbox)
                .calculateRetryableSubmissionFee(l2CallData.length, block.basefee);

            sendTxToL2CustomRefund({
                _inbox: l2ChainToUpdate.inbox, // target inbox
                _to: l2ChainToUpdate.securityCouncilUpgradeExecutor, // target l2 address
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

    /// @notice Register new DAO governed L2 chain so its security councils get updated. Callable by DAO.
    /// @param l2ChainToUpdate new governed L2 chain
    function registerL2Chain(L2ChainToUpdate memory l2ChainToUpdate) external onlyOwner {
        _registerL2Chain(l2ChainToUpdate);
    }

    /// @notice Remove L2 chain so it's security council is no longer updated
    /// @param chainID chainID of chain to remove
    function removeL2Chain(uint256 chainID) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < l2ChainsToUpdateArr.length; i++) {
            if (chainID == l2ChainsToUpdateArr[i].chainID) {
                delete l2ChainsToUpdateArr[i];
                return true;
            }
        }
        revert("L1SecurityCouncilUpdateRouter: chain not found");
    }

    function _registerL2Chain(L2ChainToUpdate memory l2ChainToUpdate) internal {
        require(
            Address.isContract(l2ChainToUpdate.inbox),
            "L1SecurityCouncilUpdateRouter: inbox not contract"
        );
        require(
            l2ChainToUpdate.securityCouncilUpgradeExecutor != address(0),
            "L1SecurityCouncilUpdateRouter: zero securityCouncilUpgradeExecutor"
        );
        require(l2ChainToUpdate.chainID != 0, "L1SecurityCouncilUpdateRouter: zero chainID");

        for (uint256 i = 0; i < l2ChainsToUpdateArr.length; i++) {
            if (l2ChainsToUpdateArr[i].chainID == l2ChainToUpdate.chainID) {
                revert("L1SecurityCouncilUpdateRouter: chain already included");
            }
        }
        l2ChainsToUpdateArr.push(l2ChainToUpdate);
        emit L2ChainRegistered(
            l2ChainToUpdate.chainID,
            l2ChainToUpdate.inbox,
            l2ChainToUpdate.securityCouncilUpgradeExecutor
        );
    }
}
