// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable-0.8/access/OwnableUpgradeable.sol";

// CHRIS: TODO: lets just use proper errors, better where we can
error InnerCallFailed(bytes reason);

// CHRIS: TODO: would be nice to constrain the execution to also call an execute function on migrating scripts
contract UpgradeExecutor is Initializable, OwnableUpgradeable {
    mapping(bytes32 => bool) public nonces;

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) public initializer {
        require(owner != address(0), "UpgradeExecutor: Zero owner");

        __Ownable_init();

        _transferOwnership(owner);
    }

    function execute(address to, uint256 amount, bytes memory data, bytes32 descriptionHash)
        public
        onlyOwner
        returns (bytes memory)
    {
        // CHRIS: TODO: is this replay protection enough?
        bytes32 executionHash = keccak256(abi.encode(to, amount, data, descriptionHash));
        // CHRIS: TODO: clean up errors
        require(!nonces[executionHash], "UpgradeExecutor: Nonce already used");
        nonces[executionHash] = true;

        (bool success, bytes memory returnData) = address(to).delegatecall(data);
        // CHRIS: TODO: do we want to require succeed here?
        // CHRIS: TODO: I think it's important that we do, or we should a provided gas limit to make sure enough has been supplied
        // CHRIS: TODO: otherwise someone could execute this with insufficient gas causing the inner call to fail, but the outer would still store the noce
        if(!success) {
            revert InnerCallFailed(returnData);
        }
        
        return returnData;
    }
}
