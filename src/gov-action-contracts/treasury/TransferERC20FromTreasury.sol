// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../address-registries/L2AddressRegistry.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library TransferERC20FromTreasury {
    function transferERC20FromTreasury(
        address _token,
        address _to,
        uint256 _amount,
        bytes32 _predecessor,
        string calldata _description,
        uint256 _delay,
        IL2AddressRegistry govAddressRegisry
    ) internal {
        require(
            Address.isContract(_token),
            "TransferERC20FromTreasury: _token address must be a contract"
        );

        IL2ArbitrumGoverner treasuryGov = govAddressRegisry.treasuryGov();
        address treasuryWalletAddress = address(govAddressRegisry.treasuryWallet());
        require(
            IERC20(_token).balanceOf(treasuryWalletAddress) >= _amount,
            "TransferERC20FromTreasury: insufficient amount to transfer"
        );
        address treasuryTimelockAddress = treasuryGov.timelock();

        bytes memory tokenTransferCallData = abi.encodeWithSelector(
            IFixedDelegateErc20Wallet.transfer.selector, _token, _to, _amount
        );

        bytes memory scheduleOperationCallData = abi.encodeWithSelector(
            IArbitrumTimelock.scheduleBatch.selector,
            [treasuryWalletAddress],
            [0],
            [tokenTransferCallData],
            _predecessor,
            keccak256(bytes(_description)), // generate salt
            _delay
        );

        treasuryGov.relay({
            target: treasuryTimelockAddress,
            value: 0,
            data: scheduleOperationCallData
        });
    }
}
