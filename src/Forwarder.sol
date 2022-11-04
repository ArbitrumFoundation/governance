// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";


contract Forwarder is Ownable {
    mapping(bytes32 => bool) nonces;

    constructor(address owner) Ownable() {
        _transferOwnership(owner);
    }

    function forward(address to, uint256 amount, bytes memory data, bytes32 proposalId)
        public
        onlyOwner
        returns (bytes memory)
    {
        // CHRIS: TODO: need better replay than this
        require(!nonces[proposalId], "Forwarder: nonce used");
        nonces[proposalId] = true;

        (bool success, bytes memory returnData) = address(to).call{value: amount}(data);
        // CHRIS: TODO: do we want to require succeed here?
        // CHRIS: TODO: I think it's important that we do, or we should a provided gas limit to make sure enough has been supplied
        // CHRIS: TODO: otherwise someone could execute this with insufficient gas causing the inner call to fail, but the outer would still store the noce
        require(success, "Forwarder: call fail");
        return returnData;
    }
}
