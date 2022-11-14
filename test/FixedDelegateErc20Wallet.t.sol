// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../src/FixedDelegateErc20Wallet.sol";
import "./util/TestUtil.sol";

import "../src/L2ArbitrumToken.sol";

import "forge-std/Test.sol";

contract FixedDelegateErc20WalletTest is Test {
    address l1TokenAddress = address(139);
    uint256 initialTokenSupply = 50_000;
    address tokenOwner = address(141);
    address delegateTo = address(152);
    address walletOwner = address(153);
    address toAddr = address(165);

    function deploy() internal returns (FixedDelegateErc20Wallet, L2ArbitrumToken) {
        L2ArbitrumToken token =
            L2ArbitrumToken(TestUtil.deployProxy(address(new L2ArbitrumToken())));
        token.initialize(l1TokenAddress, initialTokenSupply, tokenOwner);

        FixedDelegateErc20Wallet wallet =
            FixedDelegateErc20Wallet(TestUtil.deployProxy(address(new FixedDelegateErc20Wallet())));
        return (wallet, token);
    }

    function deployAndInit() internal returns (FixedDelegateErc20Wallet, L2ArbitrumToken) {
        (FixedDelegateErc20Wallet wallet, L2ArbitrumToken token) = deploy();

        wallet.initialize(address(token), delegateTo, walletOwner);
        return (wallet, token);
    }

    function testInit() external {
        (FixedDelegateErc20Wallet wallet, L2ArbitrumToken token) = deploy();

        wallet.initialize(address(token), delegateTo, walletOwner);

        assertEq(token.delegates(address(wallet)), delegateTo, "Delegates");
        assertEq(wallet.owner(), walletOwner, "Owner");
    }

    function testInitZeroToken() external {
        (FixedDelegateErc20Wallet wallet, L2ArbitrumToken token) = deploy();

        vm.expectRevert("FixedDelegateErc20Wallet: zero token address");
        wallet.initialize(address(0), delegateTo, walletOwner);

        vm.expectRevert("FixedDelegateErc20Wallet: zero delegateTo address");
        wallet.initialize(address(token), address(0), walletOwner);
        vm.expectRevert("FixedDelegateErc20Wallet: zero owner address");
        wallet.initialize(address(token), delegateTo, address(0));
    }

    function testTransfer() external {
        (FixedDelegateErc20Wallet wallet, L2ArbitrumToken token) = deployAndInit();

        vm.prank(tokenOwner);
        token.transfer(address(wallet), 10_000);

        vm.prank(walletOwner);
        wallet.transfer(address(token), toAddr, 7);
        assertEq(token.balanceOf(toAddr), 7, "Received");
    }

    function testTransferNotOwner() external {
        (FixedDelegateErc20Wallet wallet, L2ArbitrumToken token) = deployAndInit();

        vm.prank(tokenOwner);
        token.transfer(address(wallet), 10_000);

        vm.expectRevert("Ownable: caller is not the owner");
        wallet.transfer(address(token), toAddr, 7);
    }
}
