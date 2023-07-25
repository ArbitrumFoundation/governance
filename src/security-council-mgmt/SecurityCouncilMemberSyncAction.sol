// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "./interfaces/IGnosisSafe.sol";
import "./SecurityCouncilMgmtUtils.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract KeyValueStore {
    mapping(uint256 => uint256) public store;

    function set(uint256 key, uint256 value) external {
        store[_computeKey(msg.sender, key)] = value;
    }

    function get(uint256 key) external view returns (uint256) {
        return _get(msg.sender, key);
    }

    function get(address owner, uint256 key) external view returns (uint256) {
        return _get(owner, key);
    }

    function _get(address owner, uint256 key) internal view returns (uint256) {
        return store[_computeKey(owner, key)];
    }

    function _computeKey(address owner, uint256 key) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(owner, key)));
    }
}

contract UpgradeActionStorage {
    KeyValueStore public immutable store;
    bytes32 public immutable actionContractId;

    error ActionAlreadyExecuted(uint256 actionId);

    constructor(KeyValueStore _store, string memory _uniqueActionName) {
        store = _store;
        actionContractId = keccak256(bytes(_uniqueActionName));
    }

    function _setExecuted(uint256 actionId) internal {
        if (_getExecuted(actionId)) {
            revert ActionAlreadyExecuted(actionId);
        }
        _set(actionId, 1);
    }

    function _getExecuted(uint256 actionId) internal view returns (bool) {
        return _get(actionId) != 0;
    }

    function _set(uint256 key, uint256 value) internal {
        store.set(_computeKey(key), value);
    }

    function _get(uint256 key) internal view returns (uint256) {
        return store.get(_computeKey(key));
    }

    function _computeKey(uint256 key) private view returns (uint256) {
        return uint256(keccak256(abi.encode(actionContractId, key)));
    }
}

/// @notice Action contract for updating security council members. Used by the security council management system.
///         Expected to be delegate called into by an Upgrade Executor
contract SecurityCouncilMemberSyncAction is UpgradeActionStorage {
    error PreviousOwnerNotFound(address targetOwner, address securityCouncil);
    error ExecFromModuleError(bytes data, address securityCouncil);
    error PrevActionNotExecuted(address securityCouncil, uint256 nonce);

    /// @dev Used in the gnosis safe as the first entry in their ownership linked list
    address public constant SENTINEL_OWNERS = address(0x1);

    constructor(KeyValueStore _store)
        UpgradeActionStorage(_store, "SecurityCouncilMemberSyncAction")
    {}

    /// @notice Updates members of security council multisig to match provided array
    /// @dev    This function contains O(n^2) operations, so doesnt scale for large numbers of members. Expected count is 12, which is acceptable.
    /// Gnosis OwnerManager handles reverting if address(0) is passed to remove/add owner
    /// @param _securityCouncil The security council to update
    /// @param _updatedMembers  The new list of members. The Security Council will be updated to have this exact list of members
    function perform(address _securityCouncil, address[] memory _updatedMembers, uint256 _nonce)
        external
    {
        // make sure the previous action was executed
        if (_nonce > 0 && !_getExecuted(actionId(_securityCouncil, _nonce - 1))) {
           revert PrevActionNotExecuted({securityCouncil: _securityCouncil, nonce: _nonce});
        }

        // set this action as executed
        _setExecuted(actionId(_securityCouncil, _nonce));

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

    function actionId(address _securityCouncil, uint256 _nonce) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(_securityCouncil, _nonce)));
    }

    /// @notice Execute provided operation via gnosis safe's trusted execTransactionFromModule entry point
    function _execFromModule(IGnosisSafe securityCouncil, bytes memory data) internal {
        if (
            !securityCouncil.execTransactionFromModule(
                address(securityCouncil), 0, data, OpEnum.Operation.Call
            )
        ) {
            revert ExecFromModuleError({data: data, securityCouncil: address(securityCouncil)});
        }
    }
}
