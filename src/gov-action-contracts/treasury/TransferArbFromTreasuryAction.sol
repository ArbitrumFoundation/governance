pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";
import "./TransferERC20FromTreasury.sol";

contract TransferArbFromTreasuryAction {
    IL2AddressRegistry public immutable govAddressRegisry;

    constructor(IL2AddressRegistry _govAddressRegisry) {
        govAddressRegisry = _govAddressRegisry;
    }

    function perform(
        address _to,
        uint256 _amount,
        bytes32 _predecessor,
        string calldata _description,
        uint256 _delay
    ) external {
        TransferERC20FromTreasury.transferERC20FromTreasury({
            _token: address(govAddressRegisry.l2ArbitrumToken()),
            _to: _to,
            _amount: _amount,
            _predecessor: _predecessor,
            _description: _description,
            _delay: _delay,
            govAddressRegisry: govAddressRegisry
        });
    }
}
