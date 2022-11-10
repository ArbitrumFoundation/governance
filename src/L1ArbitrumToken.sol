// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@arbitrum/token-bridge-contracts/tokenbridge/ethereum/ICustomToken.sol";
import "./TransferAndCallToken.sol";

interface INovaArbOneReverseToken is ArbitrumEnabledToken {
    struct RegistrationParams {
        address l2TokenAddress;
        uint256 maxSubmissionCostForCustomGateway;
        uint256 maxSubmissionCostForRouter;
        uint256 maxGasForCustomGateway;
        uint256 maxGasForRouter;
        uint256 gasPriceBid;
        uint256 valueForGateway;
        uint256 valueForRouter;
        address creditBackAddress;
    }

    function registerTokenOnL2(
        RegistrationParams memory arbOneParams,
        RegistrationParams memory novaParams
    ) external payable;

    function transferFrom(address sender, address recipient, uint256 amount)
        external
        returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function bridgeMint(address account, uint256 amount) external;

    function bridgeBurn(address account, uint256 amount) external;
}

interface IL1CustomGateway {
    function registerTokenToL2(
        address _l2Address,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress
    ) external payable returns (uint256);
}

interface IGatewayRouter {
    function setGateway(
        address _gateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress
    ) external payable returns (uint256);
}

// CHRIS: TODO: docs up in here?

contract L1ArbitrumToken is
    INovaArbOneReverseToken,
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    TransferAndCallToken
{
    string private constant NAME = "Arbitrum";
    string private constant SYMBOL = "ARB";
    uint16 private constant MAGIC_ARB_ONE = 0xa4b1;

    bool private shouldRegisterGateway;

    address public arbOneRouter;
    address public arbOneGateway;
    address public novaRouter;
    address public novaGateway;

    constructor() {
        _disableInitializers();
    }

    /// @dev we only set shouldRegisterGateway to true when in `registerTokenOnL2`
    function isArbitrumEnabled() external view override returns (uint8) {
        require(shouldRegisterGateway, "L1ArbitrumToken: not expecting gateway registration");
        return uint8(MAGIC_ARB_ONE);
    }

    modifier onlyArbOneGateway() {
        require(msg.sender == arbOneGateway, "L1ArbitrumToken: only l1 arb one gateway");
        _;
    }

    function initialize(
        address _arbOneRouter,
        address _arbOneGateway,
        address _novaRouter,
        address _novaGateway
    ) public initializer {
        require(_arbOneRouter != address(0), "L1ArbitrumToken: zero arb one router");
        require(_arbOneGateway != address(0), "L1ArbitrumToken: zero arb one gateway");
        require(_novaRouter != address(0), "L1ArbitrumToken: zero nova router");
        require(_novaGateway != address(0), "L1ArbitrumToken: zero nova gateway");

        __ERC20_init(NAME, SYMBOL);
        __ERC20Permit_init(NAME);

        arbOneGateway = _arbOneGateway;
        arbOneRouter = _arbOneRouter;
        novaGateway = _novaGateway;
        novaRouter = _novaRouter;
    }

    function bridgeMint(address account, uint256 amount)
        public
        override (INovaArbOneReverseToken)
        onlyArbOneGateway
    {
        _mint(account, amount);
    }

    function bridgeBurn(address account, uint256 amount)
        public
        override (INovaArbOneReverseToken)
        onlyArbOneGateway
    {
        _burn(account, amount);
    }

    function registerTokenOnL2(
        RegistrationParams memory arbOneParams,
        RegistrationParams memory novaParams
    ) public payable {
        // we temporarily set `shouldRegisterGateway` to true for the callback in registerTokenToL2 to succeed
        // CHRIS: TODO: better comments about this stuff
        bool prev = shouldRegisterGateway;
        shouldRegisterGateway = true;

        IL1CustomGateway(arbOneGateway).registerTokenToL2{value: arbOneParams.valueForGateway}(
            arbOneParams.l2TokenAddress,
            arbOneParams.maxGasForCustomGateway,
            arbOneParams.gasPriceBid,
            arbOneParams.maxSubmissionCostForCustomGateway,
            arbOneParams.creditBackAddress
        );

        IGatewayRouter(arbOneRouter).setGateway{value: arbOneParams.valueForRouter}(
            arbOneGateway,
            arbOneParams.maxGasForRouter,
            arbOneParams.gasPriceBid,
            arbOneParams.maxSubmissionCostForRouter,
            arbOneParams.creditBackAddress
        );

        IL1CustomGateway(novaGateway).registerTokenToL2{value: novaParams.valueForGateway}(
            novaParams.l2TokenAddress,
            novaParams.maxGasForCustomGateway,
            novaParams.gasPriceBid,
            novaParams.maxSubmissionCostForCustomGateway,
            novaParams.creditBackAddress
        );

        IGatewayRouter(novaRouter).setGateway{value: novaParams.valueForRouter}(
            novaGateway,
            novaParams.maxGasForRouter,
            novaParams.gasPriceBid,
            novaParams.maxSubmissionCostForRouter,
            novaParams.creditBackAddress
        );

        shouldRegisterGateway = prev;
    }

    function balanceOf(address account)
        public
        view
        override (ERC20Upgradeable, INovaArbOneReverseToken, IERC20Upgradeable)
        returns (uint256 amount)
    {
        return ERC20Upgradeable.balanceOf(account);
    }

    function transferFrom(address sender, address recipient, uint256 amount)
        public
        override (ERC20Upgradeable, INovaArbOneReverseToken, IERC20Upgradeable)
        returns (bool)
    {
        return ERC20Upgradeable.transferFrom(sender, recipient, amount);
    }
}
