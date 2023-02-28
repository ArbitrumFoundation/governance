// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NoteStore {
    event NoteAdded(
        bytes32 id,
        address indexed sender,
        address indexed author,
        bytes32 indexed note,
        uint256 val
    );

    struct Note {
        address sender;
        address author;
        bytes32 note;
        uint256 val;
    }

    mapping(bytes32 => Note) public notes;

    function noteId(address sender, address author, bytes32 note, uint256 val)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(sender, author, note, val));
    }

    function add(address author, bytes32 note) public payable {
        bytes32 id = noteId(msg.sender, author, note, msg.value);
        require(!exists(id), "Note already added");

        notes[id] = Note({sender: msg.sender, author: author, note: note, val: msg.value});

        emit NoteAdded(id, msg.sender, author, note, msg.value);
    }

    function exists(bytes32 id) public view returns (bool) {
        return notes[id].sender != address(0);
    }
}

contract TestUpgrade {
    function upgrade(NoteStore noteStore, bytes32 note) public {
        noteStore.add(msg.sender, note);
    }

    function upgradeWithValue(NoteStore noteStore, bytes32 note) public payable {
        noteStore.add{value: msg.value}(msg.sender, note);
    }
}
