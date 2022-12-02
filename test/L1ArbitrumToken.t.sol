// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "../src/L1ArbitrumToken.sol";
import "./util/TestUtil.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "forge-std/Test.sol";

contract MockGateway {
    address public l2Address;
    uint256 public maxGas;
    uint256 public gasPriceBid;
    uint256 public maxSubmissionCost;
    address public creditBackAddress;
    uint256 public value;

    function registerTokenToL2(
        address _l2Address,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress
    ) public payable returns (uint256) {
        require(
            ArbitrumEnabledToken(msg.sender).isArbitrumEnabled() == uint8(uint16(0xa4b1)),
            "NOT_ARB_ENABLED"
        );

        l2Address = _l2Address;
        maxGas = _maxGas;
        gasPriceBid = _gasPriceBid;
        maxSubmissionCost = _maxSubmissionCost;
        creditBackAddress = _creditBackAddress;
        value = msg.value;

        return 2;
    }
}

contract MockRouter {
    using Address for address;

    address public gateway;
    uint256 public maxGas;
    uint256 public gasPriceBid;
    uint256 public maxSubmissionCost;
    address public creditBackAddress;
    uint256 public value;

    function setGateway(
        address _gateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress
    ) external payable returns (uint256) {
        require(
            ArbitrumEnabledToken(msg.sender).isArbitrumEnabled() == uint8(uint16(0xa4b1)),
            "NOT_ARB_ENABLED"
        );
        require(_gateway.isContract(), "NOT_TO_CONTRACT");

        gateway = _gateway;
        maxGas = _maxGas;
        gasPriceBid = _gasPriceBid;
        maxSubmissionCost = _maxSubmissionCost;
        creditBackAddress = _creditBackAddress;
        value = msg.value;

        return 1;
    }
}

contract L1ArbitrumTokenTest is Test {
    address arbOneRouter = address(137);
    address arbOneGateway = address(138);
    address novaRouter = address(139);
    address novaGateway = address(140);

    address user = address(141);

    INovaArbOneReverseToken.RegistrationParams novaParams = INovaArbOneReverseToken
        .RegistrationParams({
        l2TokenAddress: address(347),
        maxSubmissionCostForCustomGateway: 31,
        maxSubmissionCostForRouter: 32,
        maxGasForCustomGateway: 33,
        maxGasForRouter: 34,
        gasPriceBid: 35,
        valueForGateway: 36,
        valueForRouter: 37,
        creditBackAddress: address(348)
    });

    function deployAndInit() internal returns (L1ArbitrumToken) {
        L1ArbitrumToken token =
            L1ArbitrumToken(TestUtil.deployProxy(address(new L1ArbitrumToken())));

        token.initialize(arbOneGateway, novaRouter, novaGateway);

        return token;
    }

    function testInit() public {
        L1ArbitrumToken token = deployAndInit();

        assertEq(token.name(), "Arbitrum", "Invalid name");
        assertEq(token.decimals(), 18, "Invalid decimals");
        assertEq(token.symbol(), "ARB", "Invalid symbol");
        assertEq(token.totalSupply(), 0, "Total supply");

        assertEq(token.arbOneGateway(), arbOneGateway, "A1 Gateway");
        assertEq(token.novaRouter(), novaRouter, "Nova Router");
        assertEq(token.novaGateway(), novaGateway, "Nova Gateway");

        vm.expectRevert("L1ArbitrumToken: not expecting gateway registration");
        token.isArbitrumEnabled();
    }

    function testInitZeroGateway() public {
        L1ArbitrumToken token =
            L1ArbitrumToken(TestUtil.deployProxy(address(new L1ArbitrumToken())));

        vm.expectRevert("L1ArbitrumToken: zero arb one gateway");
        token.initialize(address(0), novaRouter, novaGateway);
    }

    function testInitZeroNovaRouter() public {
        L1ArbitrumToken token =
            L1ArbitrumToken(TestUtil.deployProxy(address(new L1ArbitrumToken())));

        vm.expectRevert("L1ArbitrumToken: zero nova router");
        token.initialize(arbOneGateway, address(0), novaGateway);
    }

    function testInitZeroNovaGateway() public {
        L1ArbitrumToken token =
            L1ArbitrumToken(TestUtil.deployProxy(address(new L1ArbitrumToken())));

        vm.expectRevert("L1ArbitrumToken: zero nova gateway");
        token.initialize(arbOneGateway, novaRouter, address(0));
    }

    function testBridgeMint() public {
        L1ArbitrumToken token = deployAndMint();

        assertEq(token.balanceOf(user), 10, "user balance");
        assertEq(token.totalSupply(), 10, "total supply");
    }

    function testBridgeMintNotGateway() public {
        L1ArbitrumToken token = deployAndInit();

        vm.expectRevert("L1ArbitrumToken: only l1 arb one gateway");
        token.bridgeMint(user, 10);
    }

    function deployAndMint() internal returns (L1ArbitrumToken) {
        L1ArbitrumToken token = deployAndInit();

        vm.prank(arbOneGateway);
        token.bridgeMint(user, 10);

        return token;
    }

    function testBridgeBurn() public {
        L1ArbitrumToken token = deployAndMint();

        vm.prank(arbOneGateway);
        token.bridgeBurn(user, 7);

        assertEq(token.balanceOf(user), 3, "User bal");
        assertEq(token.totalSupply(), 3, "Total supply");
    }

    function testBridgeBurnNotGateway() public {
        L1ArbitrumToken token = deployAndMint();

        vm.expectRevert("L1ArbitrumToken: only l1 arb one gateway");
        token.bridgeBurn(user, 7);
    }

    function testRegisterTokenOnL2() public {
        L1ArbitrumToken token =
            L1ArbitrumToken(TestUtil.deployProxy(address(new L1ArbitrumToken())));

        MockRouter a1Router = new MockRouter();
        MockGateway a1Gateway = new MockGateway();
        MockRouter n1Router = new MockRouter();
        MockGateway n1Gateway = new MockGateway();

        token.initialize(address(a1Gateway), address(n1Router), address(n1Gateway));

        token.registerTokenOnL2{value: novaParams.valueForGateway + novaParams.valueForRouter}(
            novaParams
        );

        assertEq(n1Gateway.l2Address(), novaParams.l2TokenAddress, "N1 credit");
        assertEq(n1Gateway.maxGas(), novaParams.maxGasForCustomGateway, "N1 max gas");
        assertEq(n1Gateway.gasPriceBid(), novaParams.gasPriceBid, "N1 gas price");
        assertEq(
            n1Gateway.maxSubmissionCost(),
            novaParams.maxSubmissionCostForCustomGateway,
            "N1 max submission"
        );
        assertEq(n1Gateway.creditBackAddress(), novaParams.creditBackAddress, "N1 credit back");
        assertEq(n1Gateway.value(), novaParams.valueForGateway, "N1 value");

        assertEq(n1Router.gateway(), address(n1Gateway), "N1r gateway");
        assertEq(n1Router.maxGas(), novaParams.maxGasForRouter, "N1r value");
        assertEq(n1Router.gasPriceBid(), novaParams.gasPriceBid, "N1r value");
        assertEq(n1Router.maxSubmissionCost(), novaParams.maxSubmissionCostForRouter, "N1r value");
        assertEq(n1Router.creditBackAddress(), novaParams.creditBackAddress, "N1r value");
        assertEq(n1Router.value(), novaParams.valueForRouter, "N1r value");
    }

    function testRegisterTokenOnL2NotEnoughVal() public {
        L1ArbitrumToken token =
            L1ArbitrumToken(TestUtil.deployProxy(address(new L1ArbitrumToken())));

        MockRouter a1Router = new MockRouter();
        MockGateway a1Gateway = new MockGateway();
        MockRouter n1Router = new MockRouter();
        MockGateway n1Gateway = new MockGateway();

        token.initialize(address(a1Gateway), address(n1Router), address(n1Gateway));

        vm.expectRevert();
        token.registerTokenOnL2{value: novaParams.valueForGateway + novaParams.valueForRouter - 1}(
            novaParams
        );
    }
}
