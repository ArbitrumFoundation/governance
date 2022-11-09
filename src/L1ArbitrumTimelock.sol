// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "./L1ArbitrumMessenger.sol";

interface IInboxSubmissionFee {
    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee)
        external
        view
        returns (uint256);
}

/// @title L1 timelock for executing propsals on L1 or forwarding them back to L2
/// @dev   Only accepts proposals from a counterparty L2 timelock
contract L1ArbitrumTimelock is TimelockControllerUpgradeable, L1ArbitrumMessenger {
    /// @dev When the target of an proposal is this magic value then the proposal
    ///      will be formed into a retryable ticket and posted to an inbox provided in
    ///      the data
    address public constant RETRYABLE_TICKET_MAGIC =
        address(bytes20(bytes("retryable ticket magic")));
    /// @notice The inbox for the L2 where governance is based
    address public inbox;
    /// @notice The timelock of the governance contract on L2
    address public l2Timelock;

    constructor() {
        _disableInitializers();
    }

    /// @notice             Initialise the L1 timelock
    /// @param minDelay     The minimum amount of delay this timelock should enforce
    /// @param proposers    Additional addresses that can schedule a proposal -
    ///                     the bridge of attached to the provided inbox will also be added as a proposer
    /// @param executors    The addresses that can execute a proposal (set address(0) for open execution)
    /// @param _inbox       The address of the inbox contract, for the L2 chain on which governance is based.
    ///                     For the Arbitrum DAO this the Arb1 inbox
    /// @param _l2Timelock  The address of the timelock on the L2 where governance is based
    ///                     For the Arbitrum DAO this the Arbitrum DAO timelock on Arb1
    function initialize(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address _inbox,
        address _l2Timelock
    ) external initializer {
        require(_inbox != address(0), "L1ArbitrumTimelock: zero inbox");
        require(_l2Timelock != address(0), "L1ArbitrumTimelock: zero l2 timelock");
        __TimelockController_init(minDelay, proposers, executors);

        inbox = _inbox;
        l2Timelock = _l2Timelock;

        // the bridge is allowed to create proposals
        // and we ensure that the l2 caller is the l2timelock
        // by using the onlyCounterpartTimelock modifier
        address bridge = address(getBridge(_inbox));
        grantRole(PROPOSER_ROLE, bridge);
        grantRole(CANCELLER_ROLE, bridge);
    }

    modifier onlyCounterpartTimelock() {
        // this bridge == msg.sender check is redundant in all the places that
        // we currently use this modifier since we call a function on super
        // that also checks the proposer role, which we enforce is in the intializer above
        // so although the msg.sender is being checked against the bridge twice we
        // still leave this check here for consistency of this function and in case
        // onlyCounterpartTimelock is used on other functions without this proposer check
        // in future
        address arbOneBridge = address(getBridge(inbox));
        require(msg.sender == arbOneBridge, "L1ArbitrumTimelock: not from bridge");

        // the outbox reports that the L2 address of the sender is the counterpart gateway
        address l2ToL1Sender = super.getL2ToL1Sender(inbox);
        require(l2ToL1Sender == l2Timelock, "L1ArbitrumTimelock: not from l2 timelock");
        _;
    }

    /// @inheritdoc TimelockControllerUpgradeable
    /// @dev Adds the restriction that only the counterparty timelock can call this func
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual override (TimelockControllerUpgradeable) onlyCounterpartTimelock {
        TimelockControllerUpgradeable.scheduleBatch(
            targets, values, payloads, predecessor, salt, delay
        );
    }

    /// @inheritdoc TimelockControllerUpgradeable
    /// @dev Adds the restriction that only the counterparty timelock can call this func
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual override (TimelockControllerUpgradeable) onlyCounterpartTimelock {
        TimelockControllerUpgradeable.schedule(target, value, data, predecessor, salt, delay);
    }

    /// @inheritdoc TimelockControllerUpgradeable
    /// @dev Adds the restriction that only the counterparty timelock can call this func
    function cancel(bytes32 id)
        public
        virtual
        override (TimelockControllerUpgradeable)
        onlyCounterpartTimelock
    {
        TimelockControllerUpgradeable.cancel(id);
    }

    /// @dev If the target is the inbox we assume a cross chain call is intended
    //       so instead of executing directly we create a retryable ticket
    function _execute(address target, uint256 value, bytes calldata data)
        internal
        virtual
        override
    {
        if (target == RETRYABLE_TICKET_MAGIC) {
            // if the target is the inbox we then we create a retryable ticket,
            // from the data object.
            (
                address targetInbox,
                address l2Target,
                uint256 l2Value,
                // it isn't strictly necessary to allow gasLimit and maxFeePerGas to be provided
                // here as these can be updated when executing the retryable on L2. However, a proposal
                // might provide reasonable values here, and in the optimistic case they will provide
                // enough gas for l2 execution, and therefore a manual redeem of the retryable on L2 won't
                // be required
                uint256 gasLimit,
                uint256 maxFeePerGas,
                bytes memory l2Calldata
            ) = abi.decode(data, (address, address, uint256, uint256, uint256, bytes));

            // submission fee is dependent on base fee, by looking this up here
            // and ensuring we send enough value to cover it we can be sure that
            // a retryable ticket will be created.
            uint256 submissionCost = IInboxSubmissionFee(inbox).calculateRetryableSubmissionFee(
                l2Calldata.length, block.basefee
            );

            // create a retryable ticket
            // note that the "value" argument has been completely ignored as it cannot . The msg.sender then needs to supply value to this
            // function to cover the calculated value.
            sendTxToL2CustomRefund(
                targetInbox,
                l2Target,
                // we set the msg.sender as the fee refund address as the sender here as it may be hard
                // for the sender here to provide the exact amount of value (that depends on the current basefee)
                // so if they provide extra the leftovers will be sent to their address on L2
                msg.sender,
                // this is the callValueRefundAddress which is able to cancel() the retryable
                // it's important that only this address, or another DAO controlled one is able to
                // cancel, otherwise anyone could cancel, and therefore block, the upgrade
                address(this),
                // the value supplied as a function arg is completely ignored and the msg.value
                // is used instead. This is to ensure that an executor will always be able to provide
                // eth to cover the submission costs
                msg.value,
                l2Value,
                L2GasParams({
                    _maxSubmissionCost: submissionCost,
                    _maxGas: gasLimit,
                    _gasPriceBid: maxFeePerGas
                }),
                l2Calldata
            );
        } else {
            super._execute(target, value, data);
        }
    }
}
