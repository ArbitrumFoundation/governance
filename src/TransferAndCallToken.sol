// SPDX-License-Identifier: MIT
// solhint-disable-next-line compiler-version
pragma solidity ^0.8.16;

// This file was copied from
// * https://github.com/OffchainLabs/token-bridge-contracts/blob/e304fa491f0574c984e80705f9f6d7cf8f0d798e/contracts/tokenbridge/libraries/TransferAndCallToken.sol
// * https://github.com/OffchainLabs/token-bridge-contracts/blob/e304fa491f0574c984e80705f9f6d7cf8f0d798e/contracts/tokenbridge/libraries/ITransferAndCall.sol
// But the version was updated from >0.6.0 <0.8.0 to ^0.8.16 and the
// imports where made from upgradeable instead of 0.6

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

interface ITransferAndCall is IERC20Upgradeable {
    function transferAndCall(address to, uint256 value, bytes memory data)
        external
        returns (bool success);

    event Transfer(address indexed from, address indexed to, uint256 value, bytes data);
}

/**
 * @notice note that implementation of ITransferAndCallReceiver is not expected to return a success bool
 */
interface ITransferAndCallReceiver {
    function onTokenTransfer(address _sender, uint256 _value, bytes memory _data) external;
}

// Implementation from https://github.com/smartcontractkit/LinkToken/blob/8fd6d624d981e39e6e3f55a72732deb9f2f832d9/contracts/v0.6/ERC677.sol
/**
 * @notice based on Implementation from https://github.com/smartcontractkit/LinkToken/blob/8fd6d624d981e39e6e3f55a72732deb9f2f832d9/contracts/v0.6/ERC677.sol
 * The implementation doesn't return a bool on onTokenTransfer. This is similar to the proposed 677 standard, but still incompatible - thus we don't refer to it as such.
 */
abstract contract TransferAndCallToken is ERC20Upgradeable, ITransferAndCall {
    /**
     * @dev transfer token to a contract address with additional data if the recipient is a contact.
     * @param _to The address to transfer to.
     * @param _value The amount to be transferred.
     * @param _data The extra data to be passed to the receiving contract.
     */
    function transferAndCall(address _to, uint256 _value, bytes memory _data)
        public
        virtual
        override
        returns (bool success)
    {
        super.transfer(_to, _value);
        emit Transfer(msg.sender, _to, _value, _data);
        if (isContract(_to)) {
            contractFallback(_to, _value, _data);
        }
        return true;
    }

    // PRIVATE

    function contractFallback(address _to, uint256 _value, bytes memory _data) private {
        ITransferAndCallReceiver receiver = ITransferAndCallReceiver(_to);
        receiver.onTokenTransfer(msg.sender, _value, _data);
    }

    function isContract(address _addr) private view returns (bool hasCode) {
        uint256 length;
        assembly {
            length := extcodesize(_addr)
        }
        return length > 0;
    }
}
