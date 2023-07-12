// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import "./UpgradeExecutor.sol";
import "./L1ArbitrumTimelock.sol";
import "./security-council-mgmt/Common.sol";

interface DefaultGovAction {
    function perform() external;
}

struct UpExecLocation {
    address inbox; // for L1, inbox should be set to address(0)
    address upgradeExecutor;
}

struct ChainAndUpExecLocation {
    uint256 chainId;
    UpExecLocation location;
}

// CHRIS: TODO: document the assumptions this exec router is making
//              eg * on an L2
//                 * only 1 up exec per chain
//                 * chains are arb chains - reachable via inboxes — or L1 (in which case inbox is address(0))
//                 * can schedule in L1 timelock
/// @notice Router for target the execution of action contracts in upgrade executors that exist on other chains
///         Upgrade executors can only be reached by going through a withdrawal and L1 timelock, so this contract
///         also include these stages when creating/scheduling a route
contract UpgradeExecRouterBuilder {
    error UpgadeExecDoesntExist(uint256 chainId);
    error UpgradeExecAlreadyExists(uint256 chindId);
    error ParamLengthMismatch(uint256 len1, uint256 len2);
    error EmptyActionBytesData(bytes[]);

    // Used as a magic value to indicate that a retryable ticket should be created by the L1 timelock
    address public constant RETRYABLE_TICKET_MAGIC = 0xa723C008e76E379c55599D2E4d93879BeaFDa79C;
    // Default args for creating a proposal, used by createProposalWithDefaulArgs and createProposalBatchWithDefaultArgs
    bytes public constant DEFAULT_GOV_ACTION_CALLDATA =
        abi.encodeWithSelector(DefaultGovAction.perform.selector);
    uint256 public constant DEFAULT_VALUE = 0;
    bytes32 public constant DEFAULT_PREDECESSOR = bytes32(0);

    // address of l1 timelock for core governance route
    address public l1TimelockAddr;
    // min delay for core l1 timelock, to be kept equivalent to value on L1. I.e., if L1 delay is increased, this should be redeployed with the new value
    uint256 public l1TimelockMinDelay;

    mapping(uint256 => UpExecLocation) upExecLocations;

    /// @param _upgradeExecutors location data for upgrade executors
    /// @param _l1ArbitrumTimelock minimum delay for L1 timelock
    /// @param _l1TimelockMinDelay address of the core gov L1 timelock
    constructor(
        ChainAndUpExecLocation[] memory _upgradeExecutors,
        address _l1ArbitrumTimelock,
        uint256 _l1TimelockMinDelay
    ) {
        if (_l1ArbitrumTimelock == address(0)) {
            revert ZeroAddress();
        }

        for (uint256 i = 0; i < _upgradeExecutors.length; i++) {
            ChainAndUpExecLocation memory chainAndUpExecLocation = _upgradeExecutors[i];
            if (chainAndUpExecLocation.location.upgradeExecutor == address(0)) {
                revert ZeroAddress();
            }
            if (upExecLocationExists(chainAndUpExecLocation.chainId)) {
                revert UpgradeExecAlreadyExists(chainAndUpExecLocation.chainId);
            }
            upExecLocations[chainAndUpExecLocation.chainId] = chainAndUpExecLocation.location;
        }

        l1TimelockAddr = _l1ArbitrumTimelock;
        l1TimelockMinDelay = _l1TimelockMinDelay;
    }
    /// @notice getter for UpExecLocation in upExecLocations mapping
    /// @param _chainId chainId for target UpExecLocation

    function upExecLocationExists(uint256 _chainId) public view returns (bool) {
        return upExecLocations[_chainId].upgradeExecutor != address(0);
    }

    /// @notice creates data for ArbSys for a batch of core governance operations
    /// @param chainIds target chain ids for actions
    /// @param actionAddresses address of action contracts (on their target chain)
    /// @param actionValues callvalues for operations
    /// @param actionDatas calldatas for actions
    /// @param timelockSalt salt for core gov l1 timelock operation
    function createActionRouteData(
        uint256[] memory chainIds,
        address[] memory actionAddresses,
        uint256[] memory actionValues,
        bytes[] memory actionDatas,
        bytes32 timelockSalt
    ) public view returns (address, bytes memory) {
        if (chainIds.length != actionAddresses.length) {
            revert ParamLengthMismatch(chainIds.length, actionAddresses.length);
        }
        if (chainIds.length != actionValues.length) {
            revert ParamLengthMismatch(chainIds.length, actionValues.length);
        }
        if (chainIds.length != actionDatas.length) {
            revert ParamLengthMismatch(chainIds.length, actionDatas.length);
        }

        address[] memory schedTargets = new address[](chainIds.length);
        uint256[] memory schedValues = new uint256[](chainIds.length);
        bytes[] memory schedData = new bytes[](chainIds.length);

        for (uint256 i = 0; i < chainIds.length; i++) {
            UpExecLocation memory upExecLocation = upExecLocations[chainIds[i]];
            if (upExecLocation.upgradeExecutor == address(0)) {
                revert UpgadeExecDoesntExist(chainIds[i]);
            }
            if (actionDatas[i].length == 0) {
                revert EmptyActionBytesData(actionDatas);
            }

            bytes memory executorData = abi.encodeWithSelector(
                UpgradeExecutor.execute.selector, actionAddresses[i], actionDatas[i]
            );

            // for L1, inbox is set to address(0):
            if (upExecLocation.inbox == address(0)) {
                schedTargets[i] = upExecLocation.upgradeExecutor;
                schedValues[i] = actionValues[i];
                schedData[i] = executorData;
            } else {
                // For L2 actions, magic is top level target, and value and calldata are encoded in payload
                schedTargets[i] = RETRYABLE_TICKET_MAGIC;
                schedValues[i] = 0;
                schedData[i] = abi.encode(
                    upExecLocation.inbox,
                    upExecLocation.upgradeExecutor,
                    actionValues[i],
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
    /// @notice creates data for ArbSys for a batch of core governance operations, using common default values for calldata and callvalue
    /// @param chainIds target chain ids for actions
    /// @param actionAddresses address of action contracts (on their target chain)
    /// @param timelockSalt salt for core gov l1 timelock operation

    function createActionRouteDataWithDefaults(
        uint256[] memory chainIds,
        address[] memory actionAddresses,
        bytes32 timelockSalt // CHRIS: TODO: can we calculate this in the contract somehow?
    ) public view returns (address, bytes memory) {
        uint256[] memory values = new uint256[](chainIds.length);
        bytes[] memory actionDatas = new bytes[](chainIds.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            actionDatas[i] = DEFAULT_GOV_ACTION_CALLDATA;
            values[i] = DEFAULT_VALUE;
        }
        return createActionRouteData(chainIds, actionAddresses, values, actionDatas, timelockSalt);
    }
}
