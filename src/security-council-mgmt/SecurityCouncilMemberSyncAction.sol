// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./interfaces/IGnosisSafe.sol";
import "./SecurityCouncilMgmtUtils.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract MemberSyncNonceTracker is Initializable {
    address upgradeExecutor;
    mapping(address => uint256) public nonces;

    function initialize(address _upgradeExecutor) public initializer {
        upgradeExecutor = _upgradeExecutor;
    }

    function setNonce(address _securityCouncil, uint256 _nonce) external {
        if (msg.sender != upgradeExecutor) {
            revert("Only upgrade executor can set nonce");
        }
        if (nonces[_securityCouncil] + 1 != _nonce) {
            revert("Nonce differs from expected value");
        }

        nonces[_securityCouncil] = _nonce;
    }
}

/// @notice Action contract for updating security council members. Used by the security council management system.
///         Expected to be delegate called into by an Upgrade Executor
contract SecurityCouncilMemberSyncAction {
    error PreviousOwnerNotFound(address targetOwner, address securityCouncil);
    error ExecFromModuleError(bytes data, address securityCouncil);

    /// @dev Used in the gnosis safe as the first entry in their ownership linked list
    address public constant SENTINEL_OWNERS = address(0x1);

    MemberSyncNonceTracker public immutable nonceTracker;

    constructor(MemberSyncNonceTracker _nonceTracker) {
        nonceTracker = _nonceTracker;
    }

    /// @notice Updates members of security council multisig to match provided array
    /// @dev    This function contains O(n^2) operations, so doesnt scale for large numbers of members. Expected count is 12, which is acceptable.
    /// Gnosis OwnerManager handles reverting if address(0) is passed to remove/add owner
    /// @param _securityCouncil The security council to update
    /// @param _updatedMembers  The new list of members. The Security Council will be updated to have this exact list of members
    function perform(address _securityCouncil, address[] memory _updatedMembers, uint256 _nonce)
        external
    {
        IGnosisSafe securityCouncil = IGnosisSafe(_securityCouncil);
        // preserve current threshold, the safe ensures that the threshold is never lower than the member count
        uint256 threshold = securityCouncil.getThreshold();

        address[] memory previousOwners = securityCouncil.getOwners();

        for (uint256 i = 0; i < _updatedMembers.length; i++) {
            address member = _updatedMembers[i];
            if (!securityCouncil.isOwner(member)) {
                _addMember(securityCouncil, member, threshold);
            }
        }

        for (uint256 i = 0; i < previousOwners.length; i++) {
            address owner = previousOwners[i];
            if (!SecurityCouncilMgmtUtils.isInArray(owner, _updatedMembers)) {
                _removeMember(securityCouncil, owner, threshold);
            }
        }

        _updateNonce(securityCouncil, _nonce);
    }

    function _addMember(IGnosisSafe securityCouncil, address _member, uint256 _threshold)
        internal
    {
        _execFromModule(
            securityCouncil,
            abi.encodeWithSelector(IGnosisSafe.addOwnerWithThreshold.selector, _member, _threshold)
        );
    }

    function _removeMember(IGnosisSafe securityCouncil, address _member, uint256 _threshold)
        internal
    {
        address previousOwner = getPrevOwner(securityCouncil, _member);
        _execFromModule(
            securityCouncil,
            abi.encodeWithSelector(
                IGnosisSafe.removeOwner.selector, previousOwner, _member, _threshold
            )
        );
    }

    function _updateNonce(IGnosisSafe securityCouncil, uint256 _nonce) internal {
        nonceTracker.setNonce(address(securityCouncil), _nonce);
    }

    function getPrevOwner(IGnosisSafe securityCouncil, address _owner)
        public
        view
        returns (address)
    {
        // owners are stored as a linked list and removal requires the previous owner
        address[] memory owners = securityCouncil.getOwners();
        address previousOwner = SENTINEL_OWNERS;
        for (uint256 i = 0; i < owners.length; i++) {
            address currentOwner = owners[i];
            if (currentOwner == _owner) {
                return previousOwner;
            }
            previousOwner = currentOwner;
        }
        revert PreviousOwnerNotFound({
            targetOwner: _owner,
            securityCouncil: address(securityCouncil)
        });
    }

    /// @notice Execute provided operation via gnosis safe's trusted execTransactionFromModule entry point
    function _execFromModule(IGnosisSafe securityCouncil, bytes memory data) internal {
        if (
            !securityCouncil.execTransactionFromModule(
                address(securityCouncil), 0, data, OpEnum.Operation.Call
            )
        ) {
            revert ExecFromModuleError({
                data: data,
                securityCouncil: address(securityCouncil)
            });
        }
    }
}
