// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@arbitrum/token-bridge-contracts/tokenbridge/arbitrum/IArbToken.sol";
import "./TransferAndCallToken.sol";

// CHRIS: TODO: check comments in all new added contracts
contract NovaArbitrumToken is ERC20PermitUpgradeable, TransferAndCallToken, IArbToken {
    string private constant NAME = "Arbitrum";
    string private constant SYMBOL = "ARB";

    address public l2Gateway;
    address public override l1Address;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _l1Address, address _l2Gateway) public initializer {
        require(_l1Address != address(0), "NovaArbitrumToken: zero l1 address");
        require(_l2Gateway != address(0), "NovaArbitrumToken: zero l2 gateway");

        __ERC20_init(NAME, SYMBOL);
        __ERC20Permit_init(NAME);

        l1Address = _l1Address;
        l2Gateway = _l2Gateway;
    }

    modifier onlyGateway() {
        require(msg.sender == l2Gateway, "NovaArbitrumToken: only l2 gateway");
        _;
    }

    function bridgeMint(address account, uint256 amount) external virtual override onlyGateway {
        _mint(account, amount);
    }

    function bridgeBurn(address account, uint256 amount) external virtual override onlyGateway {
        _burn(account, amount);
    }
}
