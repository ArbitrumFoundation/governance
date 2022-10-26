// SPDX-License-Identifier: Apache-2.0
// CHRIS: TODO: this version stuff is stupid - we should update our other files?
pragma solidity 0.8.16;

// CHRIS: TODO: we changed to 0.8 everywhere - do we want to do that?
import "@openzeppelin/contracts-upgradeable-0.8/governance/TimelockControllerUpgradeable.sol";
import "./L1ArbitrumMessenger.sol";

// CHRIS: TODO: if governance is upgradeable then what about the timelocks?
// CHRIS: TODO: if the timelocks are upgradeable is that ok?

// CHRIS: TODO: we could do this with a custom gnosis safe module instead

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
        // however we ensure that the actual caller is the l2timelock
        // by using the onlyCounterpartTimelock modifier
        address bridge = address(getBridge(_inbox));
        grantRole(PROPOSER_ROLE, bridge);
    }

    modifier onlyCounterpartTimelock() {
        // CHRIS: why do we do this?
        // address _inbox = inbox;

        // a message coming from the counterpart gateway was executed by the bridge
        address bridge = address(super.getBridge(inbox));
        require(msg.sender == bridge, "NOT_FROM_BRIDGE");

        // and the outbox reports that the L2 address of the sender is the counterpart gateway
        address l2ToL1Sender = super.getL2ToL1Sender(inbox);
        require(l2ToL1Sender == l2Timelock, "ONLY_COUNTERPART_TIMELOCK");
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
}
