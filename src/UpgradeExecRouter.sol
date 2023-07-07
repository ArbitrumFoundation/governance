// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";

import "./UpgradeExecutor.sol";
import "./L1ArbitrumTimelock.sol";

interface DefaultGovAction {
    function perform() external;
}

struct UpExecLocation {
    address inbox;
    address upgradeExecutor;
}

struct ChainAndUpExecLocation {
    uint256 chainId;
    UpExecLocation location;
}

library UpgradeExecutorLocationsLib {
    function exists(mapping(uint256 => UpExecLocation) storage locations, uint256 chainId)
        internal
        view
        returns (bool)
    {
        return locations[chainId].upgradeExecutor != address(0);
    }

    function add(
        mapping(uint256 => UpExecLocation) storage locations,
        ChainAndUpExecLocation memory _upExecLocation
    ) internal {
        require(
            !exists(locations, _upExecLocation.chainId),
            "UpgradeExecutorLocations: upgrade executor already exists"
        );
        locations[_upExecLocation.chainId] = _upExecLocation.location;
    }

    function remove(mapping(uint256 => UpExecLocation) storage locations, uint256 chainId)
        internal
    {
        require(
            exists(locations, chainId), "UpgradeExecutorLocations: upgrade executor does not exist"
        );
        delete locations[chainId];
    }
}

// CHRIS: TODO: document the assumptions this exec router is making
//              eg * on an L2
//                 * only 1 up exec per chain
//                 * chains are arb chains - reachable via inboxes
//                 * can schedule in L1 timelock
/// @notice Router for target the execution of action contracts in upgrade executors that exist on other chains
///         Upgrade executors can only be reached by going through a withdrawal and L1 timelock, so this contract
///         also include these stages when creating/scheduling a route
contract UpgradeExecRouter is Initializable, AccessControlUpgradeable {
    using UpgradeExecutorLocationsLib for mapping(uint256 => UpExecLocation);

    bytes32 public constant ACTION_SCHEDULER_ROLE = keccak256("ACTION_SCHEDULER_ROLE");
    // Used as a magic value to indicate that a retryable ticket should be created by the L1 timelock
    address public constant RETRYABLE_TICKET_MAGIC = 0xa723C008e76E379c55599D2E4d93879BeaFDa79C;
    // Default args for creating a proposal, used by createProposalWithDefaulArgs and createProposalBatchWithDefaultArgs
    bytes public constant DEFAULT_GOV_ACTION_CALLDATA =
        abi.encodeWithSelector(DefaultGovAction.perform.selector);
    uint256 public constant DEFAULT_VALUE = 0;
    bytes32 public constant DEFAULT_PREDECESSOR = bytes32(0);

    address public l1TimelockAddr;
    uint256 public l1TimelockMinDelay;
    mapping(uint256 => UpExecLocation) upExecLocations;

    // CHRIS: TODO: need to emit these
    event UpExecLocationAdded(ChainAndUpExecLocation chain);
    event UpExecLocationRemoved(ChainAndUpExecLocation chain);
    event MinL1TimelockDelaySet(uint256 indexed newMinTimelockDelay);
    // CHRIS: TODO: need to add events for the scheduling, maybe for the routes?

    constructor() {
        _disableInitializers();
    }

    /// @param _upgradeExecutors todo
    /// @param _admin address of the admin role
    /// @param _actionScheduler address of the action scheduler (l2 gov timelock)
    /// @param _minL1TimelockDelay minimum delay for L1 timelock
    /// @param _l1ArbitrumTimelock address of the core gov L1 timelock
    function initialize(
        ChainAndUpExecLocation[] memory _upgradeExecutors,
        address _admin,
        address _actionScheduler,
        address _l1ArbitrumTimelock,
        uint256 _minL1TimelockDelay
    ) external initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        // CHRIS: TODO: make this an array so we can add the manager? not necessary atm since we use route
        _grantRole(ACTION_SCHEDULER_ROLE, _actionScheduler);

        for (uint256 i = 0; i < _upgradeExecutors.length; i++) {
            upExecLocations.add(_upgradeExecutors[i]);
        }

        l1TimelockAddr = _l1ArbitrumTimelock;
        _setMinL1TimelockDelay(_minL1TimelockDelay);
    }

    /// @notice Add a new chain to be used for governance actions
    function addUpgradeExecutor(ChainAndUpExecLocation memory _upExecLocation)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        upExecLocations.add(_upExecLocation);
    }

    /// @notice Remove a chain to be used for governance actions
    function removeChain(uint256 _chainId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        upExecLocations.remove(_chainId);
    }

    function _setMinL1TimelockDelay(uint256 _minL1TimelockDelay) internal {
        l1TimelockMinDelay = _minL1TimelockDelay;
        emit MinL1TimelockDelaySet(_minL1TimelockDelay);
    }

    function setMinL1TimelockDelay(uint256 _minL1TimelockDelay)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setMinL1TimelockDelay(_minL1TimelockDelay);
    }

    function routeActions(
        uint256[] memory chainIds,
        address[] memory actionAddresses,
        uint256[] memory actionDatavalues,
        bytes[] memory actionData,
        bytes32 timelockSalt
    ) public view returns (address, bytes memory) {
        require(chainIds.length == actionAddresses.length, "CoreProposalCreator: length mismatch");
        require(chainIds.length == actionDatavalues.length, "CoreProposalCreator: length mismatch");
        require(chainIds.length == actionData.length, "CoreProposalCreator: length mismatch");

        address[] memory schedTargets = new address[](chainIds.length);
        uint256[] memory schedValues = new uint256[](chainIds.length);
        bytes[] memory schedData = new bytes[](chainIds.length);
        //CHRIS: TODO: check arrays are same length
        for (uint256 i = 0; i < chainIds.length; i++) {
            require(
                upExecLocations.exists(chainIds[i]),
                "UpgradeExecRouter: Upgrade exec location does not exist"
            );
            UpExecLocation memory upExecLocation = upExecLocations[chainIds[i]];

            bytes memory executorData = abi.encodeWithSelector(
                UpgradeExecutor.execute.selector, actionAddresses[i], actionData[i]
            );

            // CHRIS: TODO: safety check that all targets and data are non zero?
            if (upExecLocation.inbox == address(0)) {
                schedTargets[i] = upExecLocation.upgradeExecutor;
                schedValues[i] = actionDatavalues[i];
                schedData[i] = executorData;
            } else {
                // For L2 actions, magic is top level target, and value and calldata are encoded in payload
                schedTargets[i] = RETRYABLE_TICKET_MAGIC;
                schedValues[i] = 0;
                schedData[i] = abi.encode(
                    upExecLocation.inbox,
                    upExecLocation.upgradeExecutor,
                    actionDatavalues[i],
                    0,
                    0,
                    executorData
                );
            }
        }

        // schedule that
        bytes memory timelockCallData = abi.encodeWithSelector(
            L1ArbitrumTimelock.scheduleBatch.selector,
            schedTargets,
            schedValues,
            schedData,
            DEFAULT_PREDECESSOR, // CHRIS: TODO: should we allow others here? could be important? no, use the complex route?
            timelockSalt,
            l1TimelockMinDelay
        );

        return (
            address(100),
            abi.encodeWithSelector(ArbSys.sendTxToL1.selector, l1TimelockAddr, timelockCallData)
        );
    }

    function routeActionsWithDefaults(
        uint256[] memory chainIds,
        address[] memory actionAddresses,
        bytes32 timelockSalt
    ) public view returns (address, bytes memory) {
        uint256[] memory values = new uint256[](chainIds.length);
        bytes[] memory actionData = new bytes[](chainIds.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            actionData[i] = DEFAULT_GOV_ACTION_CALLDATA;
            values[i] = DEFAULT_VALUE;
        }
        return routeActions(chainIds, actionAddresses, values, actionData, timelockSalt);
    }

    function scheduleActions(
        uint256[] memory chainIds,
        address[] memory actionAddresses,
        uint256[] memory values,
        bytes[] memory actionData,
        bytes32 timelockSalt
    ) public onlyRole(ACTION_SCHEDULER_ROLE) {
        (address to, bytes memory payload) =
            routeActions(chainIds, actionAddresses, values, actionData, timelockSalt);
        // CHRIS: TODO: use OZ lib for this
        (bool res,) = to.call(payload);
        require(res, "CoreProposalCreator: Call failed");
    }

    function scheduleActionsWithDefaults(
        uint256[] memory chainIds,
        address[] memory actionAddresses,
        bytes32 timelockSalt
    ) public onlyRole(ACTION_SCHEDULER_ROLE) {
        (address to, bytes memory payload) =
            routeActionsWithDefaults(chainIds, actionAddresses, timelockSalt);
        // CHRIS: TODO: use OZ lib for this
        (bool res,) = to.call(payload);
        require(res, "CoreProposalCreator: Call failed");
    }
}
