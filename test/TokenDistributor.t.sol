// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/TokenDistributor.sol";
import "../src/L2ArbitrumToken.sol";
import "../src/Util.sol";
import "./util/TestUtil.sol";

import "forge-std/Test.sol";

contract TokenDistributorTest is Test {
    address l1Token = address(100_000_001);
    uint256 initialSupply = 1000;
    address tokenOwner = address(100_000_002);
    address payable sweepReceiver = payable(address(100_000_003));
    uint256 tdBalance = 400;
    uint256 currentBlockNumber = 200;
    uint256 claimPeriodStart = currentBlockNumber + 10;
    uint256 claimPeriodEnd = claimPeriodStart + 20;
    address tdOwner = address(100_000_004);
    uint256 currentBlockTimestamp = 100;
    address delegateTo = address(198);

    function deployToken() public returns (L2ArbitrumToken) {
        vm.roll(currentBlockNumber);

        L2ArbitrumToken testToken =
            L2ArbitrumToken(TestUtil.deployProxy(address(new L2ArbitrumToken())));
        testToken.initialize(l1Token, initialSupply, tokenOwner);

        return (testToken);
    }

    function deploy() public returns (TokenDistributor, L2ArbitrumToken) {
        L2ArbitrumToken token = deployToken();
        TokenDistributor td = new TokenDistributor(
            IERC20VotesUpgradeable(address(token)),
            sweepReceiver,
            tdOwner,
            claimPeriodStart,
            claimPeriodEnd,
            delegateTo
        );

        return (td, token);
    }

    function deployInitAndDeposit(uint256 amount)
        public
        returns (TokenDistributor, L2ArbitrumToken)
    {
        (TokenDistributor td, L2ArbitrumToken token) = deploy();
        vm.prank(tokenOwner);
        token.transfer(address(td), amount);

        return (td, token);
    }

    function testDoesDeploy() external {
        (TokenDistributor td, L2ArbitrumToken token) = deploy();

        assertEq(address(td.token()), address(token), "Invalid token");
        assertEq(td.sweepReceiver(), sweepReceiver, "Invalid receiver");
        assertEq(td.totalClaimable(), 0, "Invalid total tokens");
        assertEq(token.balanceOf(address(td)), 0, "Invalid balance");
        assertEq(td.claimPeriodStart(), claimPeriodStart, "Invalid claim start");
        assertEq(td.claimPeriodEnd(), claimPeriodEnd, "Invalid claim end");
        assertEq(td.claimableTokens(sweepReceiver), 0, "Invalid claimable amount");
        assertEq(token.delegates(address(td)), delegateTo, "Invalid delegate to");
    }

    function testZeroToken() public {
        vm.expectRevert("TokenDistributor: zero token address");
        new TokenDistributor(
            IERC20VotesUpgradeable(address(0)),
            sweepReceiver,
            tdOwner,
            claimPeriodStart,
            claimPeriodEnd,
            delegateTo
        );
    }

    function testZeroReceiver() public {
        L2ArbitrumToken token = deployToken();
        vm.expectRevert("TokenDistributor: zero sweep address");
        new TokenDistributor(
            IERC20VotesUpgradeable(address(token)),
            payable(address(0)),
            tdOwner,
            claimPeriodStart,
            claimPeriodEnd,
            delegateTo
        );
    }

    function testZeroOwner() public {
        L2ArbitrumToken token = deployToken();
        vm.expectRevert("TokenDistributor: zero owner address");
        new TokenDistributor(
            IERC20VotesUpgradeable(address(token)),
            sweepReceiver,
            address(0),
            claimPeriodStart,
            claimPeriodEnd,
            delegateTo
        );
    }

    function testOldClaimStart() public {
        L2ArbitrumToken token = deployToken();
        vm.roll(claimPeriodStart + 1);
        vm.expectRevert("TokenDistributor: start should be in the future");
        new TokenDistributor(
            IERC20VotesUpgradeable(address(token)),
            sweepReceiver,
            tdOwner,
            claimPeriodStart,
            claimPeriodEnd,
            delegateTo
        );
    }

    function testClaimStartAfterClaimEnd() public {
        L2ArbitrumToken token = deployToken();
        vm.expectRevert("TokenDistributor: start should be before end");
        new TokenDistributor(
            IERC20VotesUpgradeable(address(token)),
            sweepReceiver,
            tdOwner,
            claimPeriodEnd,
            claimPeriodStart,
            delegateTo
        );
    }

    function testZeroDelegateTo() public {
        L2ArbitrumToken token = deployToken();
        vm.expectRevert("TokenDistributor: zero delegate to");
        new TokenDistributor(
            IERC20VotesUpgradeable(address(token)),
            sweepReceiver,
            tdOwner,
            claimPeriodStart,
            claimPeriodEnd,
            address(0)
        );
    }

    function testDoesDeployAndDeposit() external {
        (TokenDistributor td, L2ArbitrumToken token) = deployInitAndDeposit(tdBalance);

        assertEq(token.balanceOf(tokenOwner), initialSupply - tdBalance, "Token owner balance");
        assertEq(token.balanceOf(address(td)), tdBalance, "Token distributor balance");
    }

    function createRecipients(uint128 start, uint32 count)
        private
        returns (
            uint256[] memory privKeys,
            address[] memory recipients,
            uint256[] memory amounts,
            uint256 sum
        )
    {
        privKeys = new uint256[](count);
        recipients = new address[](count);
        amounts = new uint256[](count);

        for (uint32 i = 0; i < count; i++) {
            privKeys[i] = uint256(start + i + 1);
            recipients[i] = vm.addr(start + i + 1);
            amounts[i] = uint256(start + i + 1);
        }

        // triangle numbers
        sum = (((start + count + 1) * (start + count)) / 2);
    }

    function setAndTestRecipients(
        TokenDistributor td,
        address[] memory recipients,
        uint256[] memory amounts,
        bytes memory revertReason,
        address caller
    ) private {
        vm.prank(caller);
        if (bytes(revertReason).length != 0) {
            vm.expectRevert(bytes(revertReason));
            td.setRecipients(recipients, amounts);
        } else {
            td.setRecipients(recipients, amounts);
            for (uint256 i = 0; i < recipients.length; i++) {
                assertEq(td.claimableTokens(recipients[i]), amounts[i]);
            }
        }
    }

    function testSetRecipients() public {
        (TokenDistributor td,) = deployInitAndDeposit(tdBalance);

        (, address[] memory recipients, uint256[] memory amounts,) = createRecipients(0, 10);
        setAndTestRecipients(td, recipients, amounts, "", tdOwner);
    }

    function testSetRecipientsTwice() public {
        (, address[] memory recipients, uint256[] memory amounts, uint256 sum) =
            createRecipients(0, 10);
        (, address[] memory recipients2, uint256[] memory amounts2, uint256 sum2) =
            createRecipients(uint128(recipients.length), 25);

        (TokenDistributor td,) = deployInitAndDeposit(sum + sum2);
        setAndTestRecipients(td, recipients, amounts, "", tdOwner);
        setAndTestRecipients(td, recipients2, amounts2, "", tdOwner);
    }

    function testSetRecipientsFailsNotOwner() public {
        (TokenDistributor td,) = deployInitAndDeposit(tdBalance);

        (, address[] memory recipients, uint256[] memory amounts,) = createRecipients(0, 10);
        setAndTestRecipients(
            td, recipients, amounts, "Ownable: caller is not the owner", address(137)
        );
    }

    function testSetRecipientsFailsNotEnoughDeposit() public {
        (, address[] memory recipients, uint256[] memory amounts, uint256 sum) =
            createRecipients(0, 10);
        (TokenDistributor td,) = deployInitAndDeposit(sum - 1);

        setAndTestRecipients(
            td, recipients, amounts, "TokenDistributor: not enough balance", tdOwner
        );
    }

    function testSetRecipientsFailsWhenAddingTwice() public {
        (, address[] memory recipients, uint256[] memory amounts, uint256 sum) =
            createRecipients(0, 10);
        (, address[] memory recipients2, uint256[] memory amounts2, uint256 sum2) =
            createRecipients(uint128(recipients.length) - 1, 5);

        (TokenDistributor td,) = deployInitAndDeposit(sum + sum2);
        setAndTestRecipients(td, recipients, amounts, "", tdOwner);
        setAndTestRecipients(
            td, recipients2, amounts2, "TokenDistributor: recipient already set", tdOwner
        );
    }

    function testSetRecipientsFailsWrongRecipientCount() public {
        (, address[] memory recipients, uint256[] memory amounts, uint256 sum) =
            createRecipients(0, 10);
        address[] memory recipients2 = new address[](recipients.length - 1);
        for (uint256 index = 0; index < recipients.length - 1; index++) {
            recipients2[index] = recipients[index];
        }

        (TokenDistributor td,) = deployInitAndDeposit(sum);

        setAndTestRecipients(
            td, recipients2, amounts, "TokenDistributor: invalid array length", tdOwner
        );
    }

    function testSetRecipientsFailsWrongAmountCount() public {
        (, address[] memory recipients, uint256[] memory amounts, uint256 sum) =
            createRecipients(0, 10);
        uint256[] memory amounts2 = new uint256[](amounts.length - 1);
        for (uint256 index = 0; index < amounts.length - 1; index++) {
            amounts2[index] = amounts[index];
        }

        (TokenDistributor td,) = deployInitAndDeposit(sum);

        setAndTestRecipients(
            td, recipients, amounts2, "TokenDistributor: invalid array length", tdOwner
        );
    }

    function deployAndSetRecipients()
        private
        returns (
            TokenDistributor,
            L2ArbitrumToken,
            uint256[] memory,
            address[] memory,
            uint256[] memory,
            uint256
        )
    {
        (TokenDistributor td, L2ArbitrumToken token) = deployInitAndDeposit(tdBalance);

        (
            uint256[] memory privKeys,
            address[] memory recipients,
            uint256[] memory amounts,
            uint256 sum
        ) = createRecipients(0, 10);
        setAndTestRecipients(td, recipients, amounts, "", tdOwner);
        return (td, token, privKeys, recipients, amounts, sum);
    }

    function testClaim() public {
        (
            TokenDistributor td,
            L2ArbitrumToken token,
            ,
            address[] memory recipients,
            uint256[] memory amounts,
        ) = deployAndSetRecipients();

        vm.roll(claimPeriodStart);
        address user = recipients[1];
        vm.prank(user);
        td.claim();

        assertEq(token.balanceOf(user), amounts[1], "Failed claim");
        assertEq(td.claimableTokens(user), 0, "Claim remains");
    }

    function testClaimFailsBeforeStart() public {
        (TokenDistributor td,,, address[] memory recipients,,) = deployAndSetRecipients();

        address user = recipients[1];
        vm.prank(user);
        vm.expectRevert("TokenDistributor: claim not started");
        td.claim();
    }

    function testClaimFailsAfterEnd() public {
        (TokenDistributor td,,, address[] memory recipients,,) = deployAndSetRecipients();

        vm.roll(claimPeriodEnd);
        address user = recipients[1];
        vm.prank(user);
        vm.expectRevert("TokenDistributor: claim ended");
        td.claim();
    }

    function testClaimFailsForUnknown() public {
        (TokenDistributor td,,,,,) = deployAndSetRecipients();

        vm.roll(claimPeriodStart);
        address user = address(137);
        vm.prank(user);
        vm.expectRevert("TokenDistributor: nothing to claim");
        td.claim();
    }

    function testClaimFailsForFalseTransfer() public {
        (
            TokenDistributor td,
            L2ArbitrumToken token,
            ,
            address[] memory recipients,
            uint256[] memory amounts,
        ) = deployAndSetRecipients();

        address user = recipients[1];
        uint256 amount = amounts[1];
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(token.transfer.selector, user, amount),
            abi.encode(false)
        );

        vm.roll(claimPeriodStart);
        vm.prank(user);
        vm.expectRevert("TokenDistributor: fail token transfer");
        td.claim();
    }

    function testClaimFailsForTwice() public {
        (TokenDistributor td,,, address[] memory recipients,,) = deployAndSetRecipients();

        address user = recipients[1];
        vm.roll(claimPeriodStart);
        vm.prank(user);
        td.claim();

        vm.prank(user);
        vm.expectRevert("TokenDistributor: nothing to claim");
        td.claim();
    }

    bytes32 private constant _DELEGATE_HASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function delegateSigHash(
        L2ArbitrumToken token,
        address delegatee,
        uint256 nonce,
        uint256 expiry
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(_DELEGATE_HASH, delegatee, nonce, expiry));
        return toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
    }

    function testClaimAndDelegate() public {
        (
            TokenDistributor td,
            L2ArbitrumToken token,
            uint256[] memory privKeys,
            address[] memory recipients,
            uint256[] memory amounts,
        ) = deployAndSetRecipients();

        vm.roll(claimPeriodStart);
        vm.warp(currentBlockTimestamp);

        uint256 expiry = currentBlockTimestamp + 10;
        address delegatee = recipients[5];
        bytes32 typedHash = delegateSigHash(token, delegatee, 0, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKeys[1], typedHash);

        vm.prank(recipients[1]);
        td.claimAndDelegate(delegatee, expiry, v, r, s);

        assertEq(token.delegates(recipients[1]), delegatee, "Delegate");
        assertEq(td.claimableTokens(recipients[1]), 0, "Claimable");
        assertEq(token.balanceOf(recipients[1]), amounts[1], "Claimable");
    }

    function testClaimAndDelegateFailsForWrongSender() public {
        (
            TokenDistributor td,
            L2ArbitrumToken token,
            uint256[] memory privKeys,
            address[] memory recipients,
            ,
        ) = deployAndSetRecipients();

        vm.roll(claimPeriodStart);
        vm.warp(currentBlockTimestamp);

        uint256 expiry = currentBlockTimestamp + 10;
        address delegatee = recipients[5];
        bytes32 typedHash = delegateSigHash(token, delegatee, 0, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKeys[1], typedHash);

        // different sender
        vm.prank(recipients[2]);
        vm.expectRevert("TokenDistributor: delegate failed");
        td.claimAndDelegate(delegatee, expiry, v, r, s);
    }

    function testClaimAndDelegateFailsForExpired() public {
        (
            TokenDistributor td,
            L2ArbitrumToken token,
            uint256[] memory privKeys,
            address[] memory recipients,
            ,
        ) = deployAndSetRecipients();

        vm.roll(claimPeriodStart);
        vm.warp(currentBlockTimestamp);

        uint256 expiry = currentBlockTimestamp - 10;
        address delegatee = recipients[5];
        bytes32 typedHash = delegateSigHash(token, delegatee, 0, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKeys[1], typedHash);

        // different sender
        vm.prank(recipients[2]);
        vm.expectRevert("ERC20Votes: signature expired");
        td.claimAndDelegate(delegatee, expiry, v, r, s);
    }

    function testClaimAndDelegateFailsWrongNonce() public {
        (
            TokenDistributor td,
            L2ArbitrumToken token,
            uint256[] memory privKeys,
            address[] memory recipients,
            ,
        ) = deployAndSetRecipients();

        vm.roll(claimPeriodStart);
        vm.warp(currentBlockTimestamp);

        uint256 expiry = currentBlockTimestamp + 10;
        address delegatee = recipients[5];
        bytes32 typedHash = delegateSigHash(token, delegatee, 1, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKeys[1], typedHash);

        vm.prank(recipients[1]);
        vm.expectRevert("TokenDistributor: delegate failed");
        td.claimAndDelegate(delegatee, expiry, v, r, s);
    }

    function testSweep() public {
        (TokenDistributor td, L2ArbitrumToken token,,,,) = deployAndSetRecipients();

        vm.roll(claimPeriodEnd);
        td.sweep();

        assertEq(token.balanceOf(address(td)), 0, "Td balance");
        assertEq(token.balanceOf(sweepReceiver), tdBalance, "Reciever balance");
        // cant test the self destruct in the same tx
    }

    function testSweepAfterClaim() public {
        (
            TokenDistributor td,
            L2ArbitrumToken token,
            ,
            address[] memory recipients,
            uint256[] memory amounts,
        ) = deployAndSetRecipients();

        vm.roll(claimPeriodStart);
        address user = recipients[5];
        vm.prank(user);
        td.claim();

        vm.roll(claimPeriodEnd);
        td.sweep();

        assertEq(token.balanceOf(address(td)), 0, "Td balance");
        assertEq(token.balanceOf(sweepReceiver), tdBalance - amounts[5], "Reciever balance");
    }

    function testSweepFailsBeforeClaimPeriodEnd() public {
        (TokenDistributor td,,,,,) = deployAndSetRecipients();

        vm.roll(claimPeriodEnd - 1);
        vm.expectRevert("TokenDistributor: not ended");
        td.sweep();
    }

    function testSweepFailsTwice() public {
        (TokenDistributor td,,,,,) = deployAndSetRecipients();

        vm.roll(claimPeriodEnd);
        td.sweep();

        vm.expectRevert("TokenDistributor: no leftovers");
        td.sweep();
    }

    function testSweepFailsForFailedTransfer() public {
        (TokenDistributor td, L2ArbitrumToken token,,,,) = deployAndSetRecipients();
        vm.mockCall(
            address(token),
            abi.encodeWithSelector(token.transfer.selector, sweepReceiver, tdBalance),
            abi.encode(false)
        );

        vm.roll(claimPeriodEnd);
        vm.expectRevert("TokenDistributor: fail token transfer");
        td.sweep();
    }

    function testWithdraw() public {
        (TokenDistributor td, L2ArbitrumToken token,,,,) = deployAndSetRecipients();

        vm.prank(tdOwner);
        td.withdraw(tdBalance - 10);

        assertEq(token.balanceOf(address(td)), 10, "Td balance");
        assertEq(token.balanceOf(tdOwner), tdBalance - 10, "Owner balance");
    }

    function testWithdrawFailsNotOwner() public {
        (TokenDistributor td, L2ArbitrumToken token,,,,) = deployAndSetRecipients();

        vm.prank(tdOwner);
        td.withdraw(tdBalance - 10);

        assertEq(token.balanceOf(address(td)), 10, "Td balance");
        assertEq(token.balanceOf(tdOwner), tdBalance - 10, "Owner balance");
    }

    function testWithdrawFailsTransfer() public {
        (TokenDistributor td, L2ArbitrumToken token,,,,) = deployAndSetRecipients();

        vm.mockCall(
            address(token),
            abi.encodeWithSelector(token.transfer.selector, tdOwner, tdBalance),
            abi.encode(false)
        );

        vm.expectRevert("TokenDistributor: fail transfer token");
        vm.prank(tdOwner);
        td.withdraw(tdBalance);
    }

    function testSetSweepReceiver() public {
        (TokenDistributor td, L2ArbitrumToken token,,,,) = deployAndSetRecipients();

        vm.mockCall(
            address(token),
            abi.encodeWithSelector(token.transfer.selector, tdOwner, tdBalance),
            abi.encode(false)
        );

        address payable newReceiver = payable(address(1397));

        vm.prank(tdOwner);
        td.setSweepReciever(newReceiver);
    }

    function testSetSweepReceiverFailsOwner() public {
        (TokenDistributor td, L2ArbitrumToken token,,,,) = deployAndSetRecipients();

        vm.mockCall(
            address(token),
            abi.encodeWithSelector(token.transfer.selector, tdOwner, tdBalance),
            abi.encode(false)
        );

        address payable newReceiver = payable(address(1397));

        vm.expectRevert("Ownable: caller is not the owner");
        td.setSweepReciever(newReceiver);
    }

    function testSetSweepReceiverFailsNullAddress() public {
        (TokenDistributor td, L2ArbitrumToken token,,,,) = deployAndSetRecipients();
        vm.prank(tdOwner);
        vm.expectRevert("TokenDistributor: zero sweep receiver address");
        td.setSweepReciever(payable(address(0)));
    }
}
