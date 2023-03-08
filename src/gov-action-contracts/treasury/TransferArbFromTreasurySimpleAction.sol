pragma solidity 0.8.16;

import "../address-registries/ArbOneGovAddressRegistry.sol";
import "./TransferERC20FromTreasury.sol";

contract TransferArbFromTreasurySimpleAction {
    IArbOneGovAddressRegistry public immutable govAddressRegisry;

    constructor(IArbOneGovAddressRegistry _govAddressRegisry) {
        govAddressRegisry = _govAddressRegisry;
    }

    function perform(address _to, uint256 _amount, string calldata _description) external {
        TransferERC20FromTreasury.transferERC20FromTreasury({
            _token: address(govAddressRegisry.l2ArbitrumToken()),
            _to: _to,
            _amount: _amount,
            _predecessor: bytes32(0),
            _description: _description,
            _delay: govAddressRegisry.treasuryGovTimelock().getMinDelay(),
            govAddressRegisry: govAddressRegisry
        });
    }
}
