// SPDX-License-Identifier: Apache-2.0
// CHRIS: TODO: this version stuff is stupid - we should update our other files?
pragma solidity 0.8.16;

// CHRIS: TODO: we changed to 0.8 everywhere - do we want to do that?
import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import "./L1ArbitrumMessenger.sol";

// CHRIS: TODO: if governance is upgradeable then what about the timelocks?
// CHRIS: TODO: if the timelocks are upgradeable is that ok?

// CHRIS: TODO: we could do this with a custom gnosis safe module instead

// contract L1ArbitrumTimelockProposer, L1ArbitrumMessenger {

//CHRIS: TODO: would need to make to pass in inbox and  and upgradable
//     function initialize(
//         address _inbox,
//         address _l2Timelock,
//     ) external initializer {
//         inbox = _inbox;
//         l2Timelock = _l2Timelock;

//         // the bridge is allowed to create proposals
//         // however we ensure that the actual caller is the l2timelock
//         // by using the onlyCounterpartTimelock modifier
//         address bridge = address(getBridge(_inbox));
//         grantRole(PROPOSER_ROLE, bridge);
//     }

//     modifier onlyCounterpartTimelock() {
//         // CHRIS: why do we do this?
//         // address _inbox = inbox;

//         // a message coming from the counterpart gateway was executed by the bridge
//         address bridge = address(super.getBridge(inbox));
//         require(msg.sender == bridge, "NOT_FROM_BRIDGE");

//         // and the outbox reports that the L2 address of the sender is the counterpart gateway
//         address l2ToL1Sender = super.getL2ToL1Sender(inbox);
//         require(l2ToL1Sender == l2Timelock, "ONLY_COUNTERPART_TIMELOCK");
//         _;
//     }

//     // allow it to call anything? no, we should call schedule

//     function schedule(
//         address l1Timelock,
//         address target,
//         uint256 value,
//         bytes calldata data,
//         bytes32 predecessor,
//         bytes32 salt,
//         uint256 delay
//     ) public virtual override (TimelockControllerUpgradeable) onlyCounterpartTimelock {
//         TimelockControllerUpgradeable(l1Timelock).schedule(target, value, data, predecessor, salt, delay);
//     }

// function scheduleBatch(
//     address l1Timelock,
//     address[] calldata targets,
//     uint256[] calldata values,
//     bytes[] calldata payloads,
//     bytes32 predecessor,
//     bytes32 salt,
//     uint256 delay
// ) public virtual  onlyCounterpartTimelock {
//     TimelockControllerUpgradeable(l1Timelock).scheduleBatch(targets, values, payloads, predecessor, salt, delay);
// }
// }

// CHRIS: TODO: create L2 ownable?

contract L1ArbitrumTimelock is TimelockControllerUpgradeable, L1ArbitrumMessenger {
    address public inbox;
    address public l2Timelock;

    function initialize(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address _inbox,
        address _l2Timelock
    ) external initializer {
        __TimelockController_init(minDelay, proposers, executors);

        inbox = _inbox;
        l2Timelock = _l2Timelock;

        // the bridge is allowed to create proposals
        // and we ensure that the l2 caller is the l2timelock
        // by using the onlyCounterpartTimelock modifier
        address bridge = address(getBridge(_inbox));
        grantRole(PROPOSER_ROLE, bridge);
    }

    modifier onlyCounterpartTimelock() {
        // the outbox reports that the L2 address of the sender is the counterpart gateway
        address l2ToL1Sender = super.getL2ToL1Sender(inbox);
        require(l2ToL1Sender == l2Timelock, "L1ArbitrumTimelock: not from l2 timelock");
        _;
    }

    // CHRIS: TODO: docs on these
    // CHRIS: TODO: i forgot, is this how we're supposed to use inheritance - should we use super?

    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual override (TimelockControllerUpgradeable) onlyCounterpartTimelock {
        TimelockControllerUpgradeable.scheduleBatch(targets, values, payloads, predecessor, salt, delay);
    }

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

    function execute(address target, uint256 value, bytes calldata payload, bytes32 predecessor, bytes32 salt)
        public
        payable
        virtual
        override
    {
        require(target != inbox, "L1ArbitrumTimelock: L1 inbox execution not allowed");
        super.execute(target, value, payload, predecessor, salt);
    }

    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual override {
        for (uint256 i = 0; i < targets.length; ++i) {
            require(targets[i] != inbox, "L1ArbitrumTimelock: L1 inbox batch execution not allowed");
        }
        super.executeBatch(targets, values, payloads, predecessor, salt);
    }

    // CHRIS: TODO: we may want to add an atomic crosschain and normal execute
    // CHRIS: TODO: this would be necessary if we want to ensure ordering here

    // CHRIS: TODO: should we stop all other calls to the inbox?
    // CHRIS: TODO: do this by overriding execute
    // CHRIS: TODO: one reason to do this is because the other execute will update the proposal - which we dont want to happen
    // CHRIS: TODO: this is unlikely/impossible because we wont be directly calling with any of the actual functions - our forwarder would need to look like our inbox
    function executeCrossChain(
        address target,
        uint256 value,
        bytes32 predecessor,
        bytes32 salt,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        bytes calldata payload
    ) public payable onlyRoleOrOpenRole(EXECUTOR_ROLE) {
        // CHRIS: TODO: clean up here
        // we need the l2forwarder in the to here. Should it be in the payload?
        // if it is we need to decode it... nasty
        // ok, since instead the to address is already the l2 forwarder

        // CHRIS: TODO: describe why it's safe always redirect calls to the inbox
        // CHRIS: TODO: and what the limitations of doing this are
        require(target == inbox, "L1ArbitrumTimelock: only inbox execution allowed cross chain");
        bytes32 id = hashOperation(target, value, payload, predecessor, salt);
        _beforeCrossChainCall(id, predecessor);

        // CHRIS: TODO: insist that value is 0?
        (address l2Target, uint256 l2Value, bytes memory l2Calldata) = abi.decode(payload, (address, uint256, bytes));

        // CHRIS: TODO: should we insist on a minimum gas limit?

        // CHRIS: TODO: remove these comments
        // when executing we store the hash of the stuff
        // this will be different if we wrap up the data in this way
        // we need to update the correct? no we want it to be forever executable?

        // CHRIS: TODO: remove this
        // encoding the location will be tricky. We either need different target paths
        // not nice
        // or we need custom stuff
        // we could form it from whatever...?
        // basically encode the location of execution or allow more free will?

        // form the crosschain payload
        // CHRIS: TODO: should we use the return value from the createRetryableTicket?

        // CHRIS: TODO: what about nova? we want to allow that too right?
        IInbox(inbox).createRetryableTicket{value: msg.value}(
            l2Target,
            l2Value,
            maxSubmissionCost,
            excessFeeRefundAddress,
            callValueRefundAddress,
            gasLimit,
            maxFeePerGas,
            l2Calldata
        );

        // CHRIS: TODO: not updating the status after executing opens us up to re-entrancy
        // CHRIS: TODO: is this a problem? should we disallow that with an explicit re-entrancy guard?

        // CHRIS: TODO: should we have a crosschaincallexecuted event?

        emit CallExecuted(id, 0, target, value, payload);
    }

    // CHRIS: TODO: add the execute batch variant?

    // CHRIS: TODO: this func below would have a naming conflict if not renamed - but why since it's private
    // CHRIS: TODO: would be really nice to re-use the super though... otherwise document that this is a copy of the inherited private
    /**
     * @dev Checks before execution of an operation's calls.
     */
    function _beforeCrossChainCall(bytes32 id, bytes32 predecessor) private view {
        require(isOperationReady(id), "TimelockController: operation is not ready");
        require(predecessor == bytes32(0) || isOperationDone(predecessor), "TimelockController: missing dependency");
    }
}
