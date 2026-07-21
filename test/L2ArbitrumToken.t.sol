// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "../src/L2ArbitrumToken.sol";
import "./util/MockTransferAndCallReceiver.sol";
import "./util/Reverter.sol";
import "forge-std/Test.sol";

contract L2ArbitrumTokenTest is Test {
    address owner = address(137);
    address mintRecipient = address(338);
    address emptyAddr = address(539);
    uint256 initialSupply = 10 * 1_000_000_000 * (10 ** 18);
    address l1Token = address(1_234_578);

    /// @dev deploys but does not init the contract
    function deploy() private returns (L2ArbitrumToken l2Token) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(new L2ArbitrumToken()),
            address(new ProxyAdmin()),
            bytes("")
        );
        l2Token = L2ArbitrumToken(address(proxy));
    }

    function deployAndInit() private returns (L2ArbitrumToken l2Token) {
        address tokenLogic = address(new L2ArbitrumToken());
        ProxyAdmin admin = new ProxyAdmin();
        l2Token = L2ArbitrumToken(
            address(new TransparentUpgradeableProxy(tokenLogic, address(admin), ""))
        );
        l2Token.initialize(l1Token, initialSupply, owner);
    }

    // test initial estimate
    function testInitialDvpEstimate(uint64 initialEstimate) public {
        L2ArbitrumToken l2Token = deployAndInit();

        // set an initial estimate
        vm.prank(owner);
        l2Token.postUpgradeInit(initialEstimate);

        assertEq(
            l2Token.getTotalDelegation(),
            initialEstimate
        );
    }

    // test no double init
    function testNoDoublePostUpgradeInit() public {
        L2ArbitrumToken l2Token = deployAndInit();

        // set an initial estimate
        vm.prank(owner);
        l2Token.postUpgradeInit(10);

        // try to set it again
        vm.prank(owner);
        vm.expectRevert("ARB: POST_UPGRADE_INIT_ALREADY_CALLED");
        l2Token.postUpgradeInit(20);
    }

    // test adjustment
    function testDvpAdjustment(
        uint64 initialEstimate,
        int64 adjustment
    ) public {
        int256 expected = int256(uint256(initialEstimate)) + int256(adjustment);

        L2ArbitrumToken l2Token = deployAndInit();

        // set an initial estimate
        vm.prank(owner);
        l2Token.postUpgradeInit(initialEstimate);

        // adjust the estimate
        vm.prank(owner);
        if (expected < 0) {
            vm.expectRevert("ARB: NEGATIVE_TOTAL_DELEGATION");
        }
        l2Token.adjustTotalDelegation(adjustment);
        if (expected < 0) {
            return;
        }

        assertEq(
            l2Token.getTotalDelegation(),
            uint256(expected)
        );
    }

    // test goes up when self delegating
    function testIncreaseDVPOnSelfDelegate() public {
        L2ArbitrumToken l2Token = deployAndInit();
        vm.prank(owner);
        l2Token.postUpgradeInit(10);

        // delegate some tokens
        vm.prank(owner);
        l2Token.delegate(owner);

        assertEq(
            l2Token.getTotalDelegation(), 10 + initialSupply
        );
    }

    // test goes up when delegating to another
    function testIncreaseDVPOnDelegateToAnother() public {
        L2ArbitrumToken l2Token = deployAndInit();
        vm.prank(owner);
        l2Token.postUpgradeInit(10);

        vm.prank(owner);
        l2Token.delegate(address(1));

        assertEq(
            l2Token.getTotalDelegation(), 10 + initialSupply
        );
    }

    // test does not change when redelegating to same or another
    function testNoChangeDVPOnRedelegateToSame() public {
        L2ArbitrumToken l2Token = deployAndInit();
        vm.prank(owner);
        l2Token.postUpgradeInit(0);

        // delegate some tokens
        vm.prank(owner);
        l2Token.delegate(owner);
        assertEq(
            l2Token.getTotalDelegation(), initialSupply
        );

        // redelegate to self again
        vm.prank(owner);
        l2Token.delegate(owner);
        assertEq(
            l2Token.getTotalDelegation(), initialSupply
        );

        // redelegate to another
        vm.prank(owner);
        l2Token.delegate(address(1));
        assertEq(
            l2Token.getTotalDelegation(), initialSupply
        );

        // redelegate to another again
        vm.prank(owner);
        l2Token.delegate(address(1));
        assertEq(
            l2Token.getTotalDelegation(), initialSupply
        );
    }

    // test goes down when undelegating
    function testDecreaseDVPOnUndelegate() public {
        L2ArbitrumToken l2Token = deployAndInit();
        vm.prank(owner);
        l2Token.postUpgradeInit(10);

        // delegate some tokens
        vm.prank(owner);
        l2Token.delegate(owner);
        assertEq(
            l2Token.getTotalDelegation(), 10 + initialSupply
        );

        // undelegate
        vm.prank(owner);
        l2Token.delegate(address(0));
        assertEq(l2Token.getTotalDelegation(), 10);
    }

    // test does not revert on underflow
    function testDvpNoRevertOnUnderflow() public {
        L2ArbitrumToken l2Token = deployAndInit();

        // delegate some tokens
        vm.prank(owner);
        l2Token.delegate(owner);

        // lower the estimate by some
        vm.prank(owner);
        l2Token.adjustTotalDelegation(-10);

        // create a snapshot so we can test transfer and undelegate
        uint256 snap = vm.snapshot();

        // undelegate should NOT REVERT
        vm.prank(owner);
        l2Token.delegate(address(0));

        // final value should be zero
        assertEq(l2Token.getTotalDelegation(), 0);

        // transfer should NOT REVERT
        vm.revertTo(snap);
        assertEq(
            l2Token.getTotalDelegation(), initialSupply - 10
        );
        vm.prank(owner);
        l2Token.transfer(address(1234), initialSupply);
        assertEq(l2Token.getTotalDelegation(), 0);
    }

    function testDvpIncreaseOnTransferToDelegator() public {
        L2ArbitrumToken l2Token = deployAndInit();

        address recipient = address(1234);

        // delegate some tokens
        vm.prank(recipient);
        l2Token.delegate(address(1));

        uint256 transferAmount = 105;

        vm.prank(owner);
        l2Token.transfer(recipient, transferAmount);

        assertEq(
            l2Token.getTotalDelegation(),
            transferAmount
        );
    }

    function testDvpNoChangeOnTransferToNonDelegator() public {
        L2ArbitrumToken l2Token = deployAndInit();

        address recipient = address(1234);

        vm.prank(owner);
        l2Token.transfer(recipient, 105);

        assertEq(l2Token.getTotalDelegation(), 0);
    }

    function testDvpNoChangeOnTransferToDelegator() public {
        L2ArbitrumToken l2Token = deployAndInit();

        address recipient = address(1234);

        // delegate some tokens
        vm.prank(recipient);
        l2Token.delegate(address(1));
        vm.prank(owner);
        l2Token.delegate(address(2));

        assertEq(l2Token.getTotalDelegation(), initialSupply);

        uint256 transferAmount = 105;

        vm.prank(owner);
        l2Token.transfer(recipient, transferAmount);

        assertEq(l2Token.getTotalDelegation(), initialSupply);
    }

    function testDvpNoChangeOnSelfTransfer() public {
        L2ArbitrumToken l2Token = deployAndInit();

        // delegate some tokens
        vm.prank(owner);
        l2Token.delegate(address(1));

        assertEq(l2Token.getTotalDelegation(), initialSupply);

        uint256 transferAmount = 105;

        vm.prank(owner);
        l2Token.transfer(owner, transferAmount);

        assertEq(l2Token.getTotalDelegation(), initialSupply);

        vm.prank(owner);
        l2Token.transfer(address(2), transferAmount);
        assertEq(
            l2Token.getTotalDelegation(), initialSupply - transferAmount
        );
        vm.prank(address(2));
        l2Token.transfer(address(2), transferAmount);
        assertEq(
            l2Token.getTotalDelegation(), initialSupply - transferAmount
        );
    }

    function testDvpDecreaseOnTransferFromDelegator() public {
        L2ArbitrumToken l2Token = deployAndInit();

        uint256 transferAmount = 105;

        vm.prank(owner);
        l2Token.delegate(address(1));

        assertEq(l2Token.getTotalDelegation(), initialSupply);

        vm.prank(owner);
        l2Token.transfer(address(2), transferAmount);
        assertEq(
            l2Token.getTotalDelegation(), initialSupply - transferAmount
        );
    }

    // test when block is before first checkpoint
    function testDvpAtBlockBeforeFirstCheckpoint() public {
        L2ArbitrumToken l2Token = deployAndInit();
        vm.prank(owner);
        l2Token.postUpgradeInit(10);

        uint256 blockNum = block.number;

        vm.roll(blockNum + 1);

        assertEq(l2Token.getTotalDelegationAt(blockNum - 1), 0);
        assertEq(l2Token.getTotalDelegationAt(blockNum), 10);
        assertEq(l2Token.getTotalDelegation(), 10);
    }

    function testNoLogicContractInit() public {
        L2ArbitrumToken token = new L2ArbitrumToken();

        vm.expectRevert("Initializable: contract is already initialized");
        token.initialize(l1Token, initialSupply, owner);
    }

    function testIsInitialised() public {
        L2ArbitrumToken l2Token = deployAndInit();

        assertEq(l2Token.name(), "Arbitrum", "Invalid name");
        assertEq(l2Token.symbol(), "ARB", "Invalid symbol");
        assertEq(l2Token.l1Address(), l1Token, "Invalid l1Address");
        assertEq(
            l2Token.nextMint(), block.timestamp + l2Token.MIN_MINT_INTERVAL(), "Invalid nextMint"
        );
        assertEq(l2Token.totalSupply(), 1e28, "Invalid totalSupply");
        assertEq(l2Token.owner(), owner, "Invalid owner");
    }

    function testDoesNotInitialiseZeroL1Token() public {
        L2ArbitrumToken l2Token = deploy();

        vm.expectRevert("ARB: ZERO_L1TOKEN_ADDRESS");
        l2Token.initialize(address(0), initialSupply, owner);
    }

    function testDoesNotInitialiseZeroInitialSup() public {
        L2ArbitrumToken l2Token = deploy();

        vm.expectRevert("ARB: ZERO_INITIAL_SUPPLY");
        l2Token.initialize(l1Token, 0, owner);
    }

    function testDoesNotInitialiseZeroOwner() public {
        L2ArbitrumToken l2Token = deploy();

        vm.expectRevert("ARB: ZERO_OWNER");
        l2Token.initialize(l1Token, initialSupply, address(0));
    }

    function validMint(
        uint256 supplyNumerator,
        string memory revertReason,
        bool warp,
        address minter
    ) public {
        L2ArbitrumToken l2Token = deployAndInit();

        uint256 additionalSupply = (initialSupply * supplyNumerator) / 100_000;

        assertEq(l2Token.balanceOf(mintRecipient), 0, "Invalid initial balance");

        if (warp) {
            vm.warp(block.timestamp + l2Token.MIN_MINT_INTERVAL());
        }
        vm.prank(minter);
        if (bytes(revertReason).length != 0) {
            vm.expectRevert(bytes(revertReason));
            l2Token.mint(mintRecipient, additionalSupply);
        } else {
            l2Token.mint(mintRecipient, additionalSupply);
            assertEq(
                l2Token.totalSupply(), initialSupply + additionalSupply, "Invalid inflated supply"
            );
            assertEq(l2Token.balanceOf(mintRecipient), additionalSupply, "Invalid final balance");
        }
    }

    function testCanMintLessThan2Percent() public {
        validMint(1357, "", true, owner);
    }

    function testCanMint2Percent() public {
        validMint(2000, "", true, owner);
    }

    function testCanMintZero() public {
        validMint(0, "", true, owner);
    }

    function testCannotMintMoreThan2Percent() public {
        validMint(2001, "ARB: MINT_TOO_MUCH", true, owner);
    }

    function testCannotMintWithoutFastForward() public {
        validMint(2000, "ARB: MINT_TOO_EARLY", false, owner);
    }

    function testCannotMintNotOwner() public {
        validMint(2000, "Ownable: caller is not the owner", false, mintRecipient);
    }

    function testCannotMintTwice() public {
        validMint(1357, "", true, owner);
        validMint(1357, "ARB: MINT_TOO_EARLY", false, owner);
    }

    function testCanMintTwiceWithWarp() public {
        validMint(1357, "", true, owner);
        validMint(1357, "", true, owner);
    }

    function testCanBurn() public {
        L2ArbitrumToken l2Token = deployAndInit();
        vm.prank(owner);
        l2Token.burn(105);
    }

    function testCanTransferAndCallContract() public {
        L2ArbitrumToken l2Token = deployAndInit();
        MockTransferAndCallReceiver receiver = new MockTransferAndCallReceiver();
        vm.prank(owner);
        l2Token.transferAndCall(address(receiver), 105, "");
    }

    function testCanTransferAndCallEmpty() public {
        L2ArbitrumToken l2Token = deployAndInit();
        vm.prank(owner);
        // doesn't revert, but nothing happens
        l2Token.transferAndCall(emptyAddr, 105, "");
    }

    function testCannotTransferAndCallNonReceiver() public {
        L2ArbitrumToken l2Token = deployAndInit();
        vm.prank(owner);
        // function sig not implemented in the token, so it should revert w/o a error string
        vm.expectRevert();
        l2Token.transferAndCall(address(l2Token), 105, "");
    }

    function testCannotTransferAndCallReverter() public {
        L2ArbitrumToken l2Token = deployAndInit();
        Reverter reverter = new Reverter();
        vm.prank(owner);
        vm.expectRevert("REVERTER_FAIL");
        l2Token.transferAndCall(address(reverter), 105, "");
    }
}
